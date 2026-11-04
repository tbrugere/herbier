--
-- Name: photo_upload_states; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE IF NOT EXISTS "public"."photo_upload_states" (
    "value" "text" NOT NULL,
    "description" "text"
);


ALTER TABLE "public"."photo_upload_states" OWNER TO "postgres";

--
-- Name: TABLE "photo_upload_states"; Type: COMMENT; Schema: public; Owner: postgres
--

COMMENT ON TABLE "public"."photo_upload_states" IS 'Upload state of a photo original.
metadata: kind=lookup, ocaml=Photo.Upload_state';


--
-- Name: photo_upload_states photo_upload_states_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY "public"."photo_upload_states"
    ADD CONSTRAINT "photo_upload_states_pkey" PRIMARY KEY ("value");


--
-- Name: photo_upload_states; Type: ROW SECURITY; Schema: public; Owner: postgres
--

ALTER TABLE "public"."photo_upload_states" ENABLE ROW LEVEL SECURITY;

--
-- Name: photo_upload_states photo_upload_states_select; Type: POLICY; Schema: public; Owner: postgres
--

CREATE POLICY "photo_upload_states_select" ON "public"."photo_upload_states" FOR SELECT TO "authenticated" USING (true);


--
-- Name: TABLE "photo_upload_states"; Type: ACL; Schema: public; Owner: postgres
--

GRANT ALL ON TABLE "public"."photo_upload_states" TO "service_role";
GRANT SELECT ON TABLE "public"."photo_upload_states" TO "authenticated";
