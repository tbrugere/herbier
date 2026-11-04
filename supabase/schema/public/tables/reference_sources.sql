--
-- Name: reference_sources; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE IF NOT EXISTS "public"."reference_sources" (
    "value" "text" NOT NULL,
    "description" "text"
);


ALTER TABLE "public"."reference_sources" OWNER TO "postgres";

--
-- Name: TABLE "reference_sources"; Type: COMMENT; Schema: public; Owner: postgres
--

COMMENT ON TABLE "public"."reference_sources" IS 'Where a plant reference or a reference payload comes from.
metadata: kind=lookup, ocaml=Reference.Source';


--
-- Name: reference_sources reference_sources_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY "public"."reference_sources"
    ADD CONSTRAINT "reference_sources_pkey" PRIMARY KEY ("value");


--
-- Name: reference_sources; Type: ROW SECURITY; Schema: public; Owner: postgres
--

ALTER TABLE "public"."reference_sources" ENABLE ROW LEVEL SECURITY;

--
-- Name: reference_sources reference_sources_select; Type: POLICY; Schema: public; Owner: postgres
--

CREATE POLICY "reference_sources_select" ON "public"."reference_sources" FOR SELECT TO "authenticated" USING (true);


--
-- Name: TABLE "reference_sources"; Type: ACL; Schema: public; Owner: postgres
--

GRANT ALL ON TABLE "public"."reference_sources" TO "service_role";
GRANT SELECT ON TABLE "public"."reference_sources" TO "authenticated";
