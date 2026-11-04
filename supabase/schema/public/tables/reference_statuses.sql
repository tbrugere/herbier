--
-- Name: reference_statuses; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE IF NOT EXISTS "public"."reference_statuses" (
    "value" "text" NOT NULL,
    "description" "text"
);


ALTER TABLE "public"."reference_statuses" OWNER TO "postgres";

--
-- Name: TABLE "reference_statuses"; Type: COMMENT; Schema: public; Owner: postgres
--

COMMENT ON TABLE "public"."reference_statuses" IS 'How complete a fetched reference payload is.
metadata: kind=lookup, ocaml=Reference.Status';


--
-- Name: reference_statuses reference_statuses_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY "public"."reference_statuses"
    ADD CONSTRAINT "reference_statuses_pkey" PRIMARY KEY ("value");


--
-- Name: reference_statuses; Type: ROW SECURITY; Schema: public; Owner: postgres
--

ALTER TABLE "public"."reference_statuses" ENABLE ROW LEVEL SECURITY;

--
-- Name: reference_statuses reference_statuses_select; Type: POLICY; Schema: public; Owner: postgres
--

CREATE POLICY "reference_statuses_select" ON "public"."reference_statuses" FOR SELECT TO "authenticated" USING (true);


--
-- Name: TABLE "reference_statuses"; Type: ACL; Schema: public; Owner: postgres
--

GRANT ALL ON TABLE "public"."reference_statuses" TO "service_role";
GRANT SELECT ON TABLE "public"."reference_statuses" TO "authenticated";
