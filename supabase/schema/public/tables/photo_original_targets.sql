--
-- Name: photo_original_targets; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE IF NOT EXISTS "public"."photo_original_targets" (
    "value" "text" NOT NULL,
    "description" "text"
);


ALTER TABLE "public"."photo_original_targets" OWNER TO "postgres";

--
-- Name: TABLE "photo_original_targets"; Type: COMMENT; Schema: public; Owner: postgres
--

COMMENT ON TABLE "public"."photo_original_targets" IS 'Where the original of a photo is kept.
metadata: kind=lookup, ocaml=Photo.Original_target';


--
-- Name: photo_original_targets photo_original_targets_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY "public"."photo_original_targets"
    ADD CONSTRAINT "photo_original_targets_pkey" PRIMARY KEY ("value");


--
-- Name: photo_original_targets; Type: ROW SECURITY; Schema: public; Owner: postgres
--

ALTER TABLE "public"."photo_original_targets" ENABLE ROW LEVEL SECURITY;

--
-- Name: photo_original_targets photo_original_targets_select; Type: POLICY; Schema: public; Owner: postgres
--

CREATE POLICY "photo_original_targets_select" ON "public"."photo_original_targets" FOR SELECT TO "authenticated" USING (true);


--
-- Name: TABLE "photo_original_targets"; Type: ACL; Schema: public; Owner: postgres
--

GRANT ALL ON TABLE "public"."photo_original_targets" TO "service_role";
GRANT SELECT ON TABLE "public"."photo_original_targets" TO "authenticated";
