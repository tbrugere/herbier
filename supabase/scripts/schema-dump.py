#!/usr/bin/env python3
# /// script
# requires-python = ">=3.12"
# dependencies = []
# ///
# ================================
# Dump the local database schema into per-object SQL files under
# supabase/schema/ so schema changes (tables, functions, policies,
# grants) show up as one reviewable git diff per object.
# Adapted from the venso project's schema-dump script.
#
# Layout:
#   supabase/schema/_database.sql                    extensions, default
#                                                    privileges, publications,
#                                                    event triggers
#   supabase/schema/<schema>/schema.sql              CREATE SCHEMA +
#                                                    schema-level grants
#   supabase/schema/<schema>/tables/<table>.sql      table + constraints,
#                                                    indexes, triggers,
#                                                    policies, grants
#   supabase/schema/<schema>/views/<view>.sql        view + rules, grants
#   supabase/schema/<schema>/functions/<fn>.sql      function(s) + grants
#   supabase/schema/<schema>/types/<type>.sql        types and domains
#
# Usage:
#   uv run supabase/scripts/schema-dump.py           # regenerate supabase/schema/
#   uv run supabase/scripts/schema-dump.py --check   # fail if the dump is stale
#
# Requires the local Supabase database to be running with this branch's
# migrations applied (`npx supabase db reset` guarantees that). The dump
# itself is `supabase db dump --local --keep-comments`: a dockerized pg_dump
# whose version matches the server, with Supabase-managed schemas excluded
# and the `-- Name: ...; Type: ...; Schema: ...` section markers kept so each
# block can be routed to its object's file. TRACKED_SCHEMAS are dumped;
# EXTENSION_SCHEMAS are skipped; a block in any other schema is a hard
# error so a new app schema can't silently drop out of tracking. pg_dump's
# randomized \restrict tokens are stripped to keep the output deterministic.
# ================================

import difflib
import re
import subprocess
import sys
import tempfile
from collections.abc import Sequence
from dataclasses import dataclass, replace
from pathlib import Path
from typing import Self

REPO_ROOT = Path(__file__).resolve().parents[2]
SCHEMA_DIR = REPO_ROOT / 'supabase' / 'schema'
DATABASE_FILE = '_database.sql'
MISC_FILE = '_misc.sql'
TRACKED_SCHEMAS = {'public'}
EXTENSION_SCHEMAS = {'extensions', 'pgmq', 'net', 'vault'}

HEADER_RE = re.compile(r'^-- Name: (?P<name>.+); Type: (?P<type>[^;]+); Schema: (?P<schema>[^;]*); Owner: (?P<owner>.*)$')
QUALIFIED_RE = re.compile(r'(?P<kind>TABLE|VIEW|MATERIALIZED VIEW|COLUMN|FUNCTION|PROCEDURE|AGGREGATE|SEQUENCE|TYPE|DOMAIN|SCHEMA|EXTENSION) (?P<rest>.+)', re.DOTALL)
INDEX_ON_RE = re.compile(r'\sON\s+(?:ONLY\s+)?"?(?P<schema>[\w$]+)"?\."?(?P<table>[\w$]+)"?')
RESTRICT_RE = re.compile(r'^-- \\(?:un)?restrict \w+\n', re.MULTILINE)
TRAILER_RE = re.compile(r'--\n-- PostgreSQL database dump complete\n--\s*\Z')

ViewNames = set[tuple[str, str]]


def run_dump(out_file: Path) -> None:
    subprocess.run(
        ['npx', '-y', 'supabase@latest', 'db', 'dump', '--local', '--keep-comments', '-f', str(out_file)],
        check=True,
        cwd=REPO_ROOT,
    )


def unquote(identifier: str) -> str:
    return identifier.replace('"', '')


def sanitize(name: str) -> str:
    return re.sub(r'[^A-Za-z0-9_.-]', '_', unquote(name))


@dataclass(frozen=True)
class Block:
    name: str
    type: str
    schema: str
    sql: str

    @classmethod
    def parse(cls, block_text: str) -> Self:
        header = HEADER_RE.match(block_text.splitlines()[1])
        assert header is not None
        return cls(name=header['name'], type=header['type'], schema=header['schema'], sql=block_text)

    def effective_schema(self) -> str | None:
        if self.schema != '-':
            return self.schema
        if self.type == 'SCHEMA':
            return unquote(self.name)
        qualified = QUALIFIED_RE.match(self.name)
        if qualified and qualified['kind'] == 'SCHEMA':
            return unquote(qualified['rest'])
        return None

    def is_included(self) -> bool:
        schema = self.effective_schema()
        if schema is None or schema in TRACKED_SCHEMAS:
            return True
        if schema in EXTENSION_SCHEMAS:
            return False
        raise SystemExit(
            f'error: block {self.name!r} ({self.type}) belongs to untracked schema {schema!r}.\n'
            f'Add it to TRACKED_SCHEMAS (to dump it) or EXTENSION_SCHEMAS (to skip it) in supabase/scripts/schema-dump.py.'
        )

    def route(self, view_names: ViewNames) -> str:
        match self.type:
            case 'SCHEMA':
                return f'{sanitize(self.name)}/schema.sql'
            case 'EXTENSION' | 'EVENT TRIGGER' | 'PUBLICATION' | 'PUBLICATION TABLE' | 'DEFAULT ACL':
                return DATABASE_FILE
            case 'TABLE' | 'VIEW' | 'MATERIALIZED VIEW' | 'SEQUENCE' | 'ROW SECURITY':
                return relation_file(self.schema, self.name, view_names)
            case 'COLUMN':
                return relation_file(self.schema, self.name.split('.')[0], view_names)
            case 'CONSTRAINT' | 'FK CONSTRAINT' | 'TRIGGER' | 'POLICY' | 'RULE':
                return relation_file(self.schema, self.name.split(' ')[0], view_names)
            case 'FUNCTION' | 'PROCEDURE' | 'AGGREGATE':
                return f'{sanitize(self.schema)}/functions/{sanitize(self.name.split("(")[0])}.sql'
            case 'TYPE' | 'DOMAIN':
                return f'{sanitize(self.schema)}/types/{sanitize(self.name)}.sql'
            case 'INDEX':
                target = INDEX_ON_RE.search(self.sql)
                if target:
                    return relation_file(target['schema'], target['table'], view_names)
                return self._fallback_file()
            case 'ACL' | 'COMMENT':
                qualified = QUALIFIED_RE.match(self.name)
                if qualified:
                    return replace(self, type=qualified['kind'], name=qualified['rest']).route(view_names)
                return self._fallback_file()
            case _:
                return self._fallback_file()

    def _fallback_file(self) -> str:
        return DATABASE_FILE if self.schema == '-' else f'{sanitize(self.schema)}/{MISC_FILE}'


@dataclass(frozen=True)
class BlockSet:
    preamble: str
    blocks: list[Block]

    @staticmethod
    def is_start_of_block(three_lines: Sequence[str]) -> bool:
        return bool(
            three_lines[0].rstrip('\n') == '--'
            and HEADER_RE.match(three_lines[1].rstrip('\n'))
            and three_lines[2].rstrip('\n') == '--'
        )

    @classmethod
    def parse(cls, text: str) -> Self:
        text = RESTRICT_RE.sub('', text)
        text = TRAILER_RE.sub('', text)
        lines = text.splitlines(keepends=True)
        starts = [i for i in range(len(lines) - 2) if cls.is_start_of_block(lines[i : i + 3])]
        if not starts:
            raise SystemExit('error: no pg_dump section markers found in the dump output')
        preamble = ''.join(lines[: starts[0]])
        blocks = []
        for start, end in zip(starts, starts[1:] + [len(lines)]):
            blocks.append(Block.parse(''.join(lines[start:end])))
        return cls(preamble, blocks)

    @property
    def view_names(self) -> ViewNames:
        return {(b.schema, unquote(b.name)) for b in self.blocks if b.type in ('VIEW', 'MATERIALIZED VIEW')}


def relation_file(schema: str, relation: str, view_names: ViewNames) -> str:
    kind_dir = 'views' if (schema, unquote(relation)) in view_names else 'tables'
    return f'{sanitize(schema)}/{kind_dir}/{sanitize(relation)}.sql'


def build_tree(dump_text: str) -> dict[str, str]:
    block_set = BlockSet.parse(dump_text)
    view_names = block_set.view_names
    files: dict[str, list[str]] = {DATABASE_FILE: [block_set.preamble]}
    for block in block_set.blocks:
        if block.is_included():
            files.setdefault(block.route(view_names), []).append(block.sql)
    return {path: ''.join(parts).rstrip('\n') + '\n' for path, parts in files.items()}


def generate() -> dict[str, str]:
    with tempfile.NamedTemporaryFile(suffix='.sql', delete=False) as tmp:
        tmp_path = Path(tmp.name)
    try:
        run_dump(tmp_path)
        return build_tree(tmp_path.read_text())
    finally:
        tmp_path.unlink(missing_ok=True)


def read_tree(root: Path) -> dict[str, str]:
    return {str(p.relative_to(root)): p.read_text() for p in root.rglob('*.sql')}


def write_tree(root: Path, files: dict[str, str]) -> None:
    for stale in root.rglob('*.sql'):
        stale.unlink()
    for empty in sorted((d for d in root.rglob('*') if d.is_dir()), reverse=True):
        if not any(empty.iterdir()):
            empty.rmdir()
    for rel_path, content in files.items():
        target = root / rel_path
        target.parent.mkdir(parents=True, exist_ok=True)
        target.write_text(content)


def check(expected: dict[str, str]) -> int:
    if not SCHEMA_DIR.is_dir():
        print(f'error: {SCHEMA_DIR} does not exist. Generate it with: uv run supabase/scripts/schema-dump.py', file=sys.stderr)
        return 1
    actual = read_tree(SCHEMA_DIR)
    stale = False
    for missing in sorted(expected.keys() - actual.keys()):
        stale = True
        print(f'missing file: supabase/schema/{missing}', file=sys.stderr)
    for extra in sorted(actual.keys() - expected.keys()):
        stale = True
        print(f'extra file: supabase/schema/{extra}', file=sys.stderr)
    for rel_path in sorted(expected.keys() & actual.keys()):
        if actual[rel_path] == expected[rel_path]:
            continue
        stale = True
        diff = difflib.unified_diff(
            actual[rel_path].splitlines(keepends=True),
            expected[rel_path].splitlines(keepends=True),
            fromfile=f'supabase/schema/{rel_path}',
            tofile=f'{rel_path} (from migrations)',
        )
        sys.stderr.writelines(diff)
    if stale:
        print(
            '\nerror: supabase/schema/ is out of date with the migrations.\n'
            '\nFix locally with:\n'
            '  npx supabase db reset\n'
            '  uv run supabase/scripts/schema-dump.py\n'
            '  git add supabase/schema\n'
            '  git commit',
            file=sys.stderr,
        )
        return 1
    print(f'ok: schema dump is up to date ({len(actual)} files).')
    return 0


def main() -> int:
    files = generate()
    if '--check' in sys.argv[1:]:
        return check(files)
    SCHEMA_DIR.mkdir(parents=True, exist_ok=True)
    write_tree(SCHEMA_DIR, files)
    print(f'dumped schema to supabase/schema/ ({len(files)} files)')
    return 0


if __name__ == '__main__':
    sys.exit(main())
