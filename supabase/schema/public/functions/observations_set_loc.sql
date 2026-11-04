--
-- Name: observations_set_loc(); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE OR REPLACE FUNCTION "public"."observations_set_loc"() RETURNS "trigger"
    LANGUAGE "plpgsql"
    SET "search_path" TO ''
    AS $$
begin
  new.loc := case
    when new.lat is null then null
    else extensions.st_setsrid(extensions.st_makepoint(new.lon, new.lat), 4326)::extensions.geography
  end;
  return new;
end;
$$;


ALTER FUNCTION "public"."observations_set_loc"() OWNER TO "postgres";

SET default_tablespace = '';

SET default_table_access_method = "heap";

--
-- Name: FUNCTION "observations_set_loc"(); Type: ACL; Schema: public; Owner: postgres
--

REVOKE ALL ON FUNCTION "public"."observations_set_loc"() FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."observations_set_loc"() TO "service_role";
