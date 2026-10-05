# PostgREST filter value parsing (from source)

Date: 2026-10-02. Source: PostgREST `main` at `45593a3dbef8a3e0ad6656a88a91b226e1e483a2`, file
`src/library/PostgREST/ApiRequest/QueryParams.hs` (`QP.hs`; permalink base
`https://github.com/PostgREST/postgrest/blob/45593a3d/src/library/PostgREST/ApiRequest/QueryParams.hs`). Cross-checked
against tags `v12.2.12` and `v13.0.8` (file then at `src/PostgREST/ApiRequest/QueryParams.hs`): every parser quoted below
is byte-identical in all three. SQL rendering: `src/library/PostgREST/Query/SqlFragment.hs` (`SF.hs`). Tests: `test/spec/Feature/Query/`.

## Summary

- A plain filter `col=op.value` is parsed as operator, **one** `.` (`pDelimiter`), then
  `pSingleVal = many anyChar`: everything after that first dot, verbatim. No quote handling, no trimming,
  no escapes. `name=eq."Hebdon"` sends the 8-character value `"Hebdon"` (quotes included) to Postgres;
  `price=gt.1.5` gives value `1.5`.
- Double quotes are interpreted only by `pQuotedValue`, used in exactly three places: elements of
  `in.(...)`, values inside `and=`/`or=` trees, and column names. Inside quotes `\x` means `x` for any `x`
  (`\"` and `\\` work, `\n` is a literal `n`); there are no other escapes.
- Unquoted list / logic-tree values end at the first `,` or `)`; `(`, `.` and spaces are ordinary.
- `eq(any).{a,b}` is not split by PostgREST: the brace string is one value handed to Postgres as a text
  array literal, so Postgres array-literal quoting applies, not PostgREST's.
- `like`/`ilike`: every `*` becomes `%` at SQL-rendering time (`T.map star`); a literal `*` cannot be expressed.
- Whitespace is skipped only around `(`, `)`, `,` of lists and logic trees and around field names; value
  text is never trimmed (a `+` in the raw query string decodes to a space).

## 1. Simple filters: value is verbatim after the first dot

`QP.hs:279-290` (`pRequestFilter`) runs `pOpExpr pSingleVal` on the whole value string.

```haskell
-- QP.hs:698-699, 710-718
pOpExpr pSVal = do
    pSimpleOp = do
      op <- simpleOperator
      pDelimiter *> (Op op <$> pSVal)
    pQuantOp = do
      op <- quantOperator
      quant <- optionMaybe $ try (between (char '(') (char ')') (try (string "any" $> QuantAny) <|> string "all" $> QuantAll))
      pDelimiter *> (OpQuant op quant <$> pSVal)
-- QP.hs:744-745, 758-759
pSingleVal = toS <$> many anyChar
pDelimiter = char '.' <?> "delimiter (.)"
```

`eq."Hebdon"` → `OpQuant OpEqual Nothing "\"Hebdon\""`; `eq.Hebdon,John` → value `Hebdon,John`; sent as an
`unknown`-typed parameter (`SF.hs:427`), so Postgres casts it.
Tests: `JsonOperatorSpec.hs:260` `num->>i=gt.0.5` (dot kept); `JsonOperatorSpec.hs:242`
`data=eq.{\"e\":1}` (quotes and braces pass through to a jsonb compare). Doctest `QP.hs:271-272`:
`pRequestFilter False ("id", "eq.1")` → `OpQuant OpEqual Nothing "1"`. No test uses `eq."..."` at top level.

## 2. `in.(...)`: quoting, escapes, terminators

```haskell
-- QP.hs:747-756
pListVal = lexeme (char '(') *> pListElement `sepBy1` char ',' <* lexeme (char ')')
pListElement = try (pQuotedValue <* notFollowedBy (noneOf ",)")) <|> (toS <$> many (noneOf ",)"))
pQuotedValue = toS <$> (char '"' *> many pCharsOrSlashed <* char '"')
  where
    pCharsOrSlashed = noneOf "\\\"" <|> (char '\\' *> anyChar)
```

An unquoted element is terminated by `,` or `)` only; those are the only characters that force quoting.
A quoted element must be directly followed by `,` or `)`, else the parser falls back to the unquoted branch
(`in.(")` yields the element `"`). Inside quotes `\` + any char yields that char: `\"` → `"`, `\\` → `\`,
`\n` → `n`. Elements are re-quoted on the SQL side into a `{...}` literal (`SF.hs:174-180`,
`pgBuildArrayLiteral`) and compared with `= ANY(...)` (`SF.hs:449-451`).
Tests (`QuerySpec.hs`): 1492 `in.(\"Hebdon, John\")`; 1506 `in.(David White,\"Hebdon, John\")`;
1514 `in.(\"Double O Seven(007)\")`; 1521 `in.(\"Double\\\"Quote\\\"McGraw\\\"\")` → `Double"Quote"McGraw"`;
1527 `in.(\"\\\\\")` → `\`; 1537 "passes any escaped char as the same char": `in.(\"D\\a\\vid W\\h\\ite\")`
→ `David White`; 1544-1554 unquoted `in.(\")` → `"`, `in.(\\)` → `\`.

## 3. `and=(...)` / `or=(...)`: same quoting, on every inner value

```haskell
-- QP.hs:883-890
pLogicTree =
  Stmnt <$> try pLogicFilter
    <|> Expr <$> pNot <*> pLogicOp <*> (lexeme (char '(') *> pLogicTree `sepBy1` lexeme (char ',') <* lexeme (char ')'))
  where
    pLogicFilter = Filter <$> pField <* pDelimiter <*> pOpExpr pLogicSingleVal
-- QP.hs:902-909
pLogicSingleVal = try (pQuotedValue <* notFollowedBy (noneOf ",)")) <|> try pPgArray <|> (toS <$> many (noneOf ",)"))
  where pPgArray = do { a <- string "{"; b <- many (noneOf "{}"); c <- string "}"; pure (toS $ a ++ b ++ c) }
```

Inside a tree the operand is `pLogicSingleVal`: quoted (same `pQuotedValue`, same escapes), or a whole
`{...}` group (so `cs.{1,2,3}` survives its commas), or unquoted up to `,` / `)`. This is the one place
where `eq."x,y"` strips the quotes. `in.(...)` inside a tree uses `pListVal` from section 2.
Tests (`AndOrParamsSpec.hs`): 209 `or=(name.eq.\"(grandchild,entity,4)\",...)`; 212
`or=(name.like.\"*ity,4*\",name.ilike.\"*ITY,5)\")`; 215 `or=(id.in.(\"1\",\"2\"),...)`; 192
`and=(arr.not.cs.{1,2,3},...)`. Docs agree (`docs/references/api/tables_views.rst:139`, example
`age_range.adj."[18,21)"`).

## 4. `eq(any).{a,b}`: braces are opaque text

`pQuantOp` (section 1) parses only the `(any)`/`(all)` modifier; the operand is still `pSVal`:
`many anyChar` at top level, `pPgArray` inside a tree. No element splitting, no PostgREST quoting.
`SF.hs:428-432, 457-460` render `quantOperator op <> " ANY(" <> unknownLiteral val <> ")"`, so Postgres
parses `{a,b}` as an array literal: `,` `"` `\` `{` `}` or padding in an element need Postgres array-literal
double quotes and backslashes. Tests: `QuerySpec.hs:1727` `id=eq(any).{3,4,5}`, 1757
`body=like(any).{%plan%,%brain%}`. UNVERIFIED: no test exercises quoted elements inside `{...}`.

## 5. Column names

```haskell
-- QP.hs:405-407, 924-927
pFieldName = pQuotedValue <|> sepByDash pIdentifier <?> "field name (* or [a..z0..9_$])"
pIdentifier = T.strip . toS <$> many1 pIdentifierChar
pIdentifierChar = letter <|> digit <|> oneOf "_ $"
```

Unquoted names allow letters, digits, `_`, `$`, spaces (trimmed at both ends) and inner `-` (`sepByDash`).
Anything else (`.`, `,`, `(`, `)`, `:`, `>`, `*`) needs double quotes, parsed by the same `pQuotedValue`
(same `\x` escape). `pTreePath` (`QP.hs:329-333`) splits the key on `.` for embed paths, so a dotted column
must be quoted or it reads as `embed.column`. Doctests `QP.hs:393-403`: `"\":\""` → `:`;
`"\" leading and trailing spaces \""` kept. Test `QuerySpec.hs:1479`:
`select=%22a.dotted.column%22,...&%22*id*%22=eq.1`.

## 6. `like` / `ilike`: `*` → `%`

```haskell
-- SF.hs:428-431, 456
    OpQuant op quant val -> " " <> quantOperator op <> " " <> case op of
        OpLike -> fmtQuant quant $ unknownLiteral (T.map star val)
        OpILike -> fmtQuant quant $ unknownLiteral (T.map star val)
    star c = if c == '*' then '%' else c
```

Done at SQL rendering, character-wise over the whole value (also the `{...}` of `like(any)`), with no
escape: a literal `*` cannot be expressed; `%` and `_` remain Postgres wildcards. Same at `v12.2.12`
(`SF.hs:376-377,403`). Tests: `QuerySpec.hs:52` `k=like.*yx`; `AndOrParamsSpec.hs:75` `name.like.*1`.

## 7. Whitespace

```haskell
-- QP.hs:323-327
ws = toS <$> many (oneOf " \t")
lexeme p = ws *> p <* ws
```

`lexeme` wraps `(` and `)` of `pListVal` and `pLogicTree`, `,` between tree branches, and `pField`
(`QP.hs:495`), never a value. Top-level values keep all spaces (`pSingleVal`); `QP.hs:197` uses
`HTTP.parseQueryReplacePlus True`, so `+` decodes to a space first. In lists `in.(a, b)` yields ` b` with
its leading space (only the parens are padded); quoted elements keep inner spaces exactly. Test
`AndOrParamsSpec.hs:219` `and=( and ( id.in.( 1, 2, 3 ) , id.eq.3 ) , ... )` passes, but all padded values
are integers, which Postgres parses leniently. UNVERIFIED: no test pins padded text values in a list; the
conclusion follows from the grammar only.
