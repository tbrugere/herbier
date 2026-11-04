--
-- Name: plants_near("extensions"."geography", double precision); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE OR REPLACE FUNCTION "public"."plants_near"("pt" "extensions"."geography", "radius_m" double precision) RETURNS SETOF "public"."plants"
    LANGUAGE "sql" STABLE
    SET "search_path" TO ''
    AS $$
  select p.* from public.plants p
  where p.deleted_at is null
    and exists (
      select 1 from public.observations o
      where o.plant_id = p.id and o.deleted_at is null
        and extensions.st_dwithin(o.loc, pt, radius_m))
$$;


ALTER FUNCTION "public"."plants_near"("pt" "extensions"."geography", "radius_m" double precision) OWNER TO "postgres";

--
-- Name: FUNCTION "plants_near"("pt" "extensions"."geography", "radius_m" double precision); Type: ACL; Schema: public; Owner: postgres
--

-- REVOKE ALL ON FUNCTION "public"."plants_near"("pt" "extensions"."geography", "radius_m" double precision) FROM PUBLIC;
-- GRANT ALL ON FUNCTION "public"."plants_near"("pt" "extensions"."geography", "radius_m" double precision) TO "authenticated";
-- GRANT ALL ON FUNCTION "public"."plants_near"("pt" "extensions"."geography", "radius_m" double precision) TO "service_role";
