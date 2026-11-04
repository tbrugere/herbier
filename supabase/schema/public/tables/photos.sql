--
-- Name: photos; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE IF NOT EXISTS "public"."photos" (
    "id" "uuid" NOT NULL,
    "owner_id" "uuid" DEFAULT "auth"."uid"() NOT NULL,
    "observation_id" "uuid" NOT NULL,
    "taken_at" timestamp with time zone NOT NULL,
    "width" integer NOT NULL,
    "height" integer NOT NULL,
    "sha256" "text" NOT NULL,
    "preview_path" "text" NOT NULL,
    "preview_bucket_key" "text",
    "original_target" "text" NOT NULL,
    "drive_file_id" "text",
    "upload_state" "text" NOT NULL,
    "created_at" timestamp with time zone NOT NULL,
    "updated_at" timestamp with time zone NOT NULL,
    "deleted_at" timestamp with time zone
);


ALTER TABLE "public"."photos" OWNER TO "postgres";

--
-- Name: TABLE "photos"; Type: COMMENT; Schema: public; Owner: postgres
--

COMMENT ON TABLE "public"."photos" IS 'A photo of an observation: the preview and where its original is kept.
metadata: id=Ids.Photo_id';


--
-- Name: COLUMN "photos"."owner_id"; Type: COMMENT; Schema: public; Owner: postgres
--

COMMENT ON COLUMN "public"."photos"."owner_id" IS 'metadata: server_only';


--
-- Name: photos photos_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY "public"."photos"
    ADD CONSTRAINT "photos_pkey" PRIMARY KEY ("id");


--
-- Name: photos_observation_id_idx; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX "photos_observation_id_idx" ON "public"."photos" USING "btree" ("observation_id");


--
-- Name: photos_owner_id_updated_at_idx; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX "photos_owner_id_updated_at_idx" ON "public"."photos" USING "btree" ("owner_id", "updated_at");


--
-- Name: photos photos_set_updated_at; Type: TRIGGER; Schema: public; Owner: postgres
--

CREATE OR REPLACE TRIGGER "photos_set_updated_at" BEFORE INSERT OR UPDATE ON "public"."photos" FOR EACH ROW EXECUTE FUNCTION "public"."set_updated_at"();


--
-- Name: photos photos_observation_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY "public"."photos"
    ADD CONSTRAINT "photos_observation_id_fkey" FOREIGN KEY ("observation_id") REFERENCES "public"."observations"("id") ON DELETE CASCADE;


--
-- Name: photos photos_original_target_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY "public"."photos"
    ADD CONSTRAINT "photos_original_target_fkey" FOREIGN KEY ("original_target") REFERENCES "public"."photo_original_targets"("value");


--
-- Name: photos photos_owner_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY "public"."photos"
    ADD CONSTRAINT "photos_owner_id_fkey" FOREIGN KEY ("owner_id") REFERENCES "auth"."users"("id") ON DELETE CASCADE;


--
-- Name: photos photos_upload_state_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY "public"."photos"
    ADD CONSTRAINT "photos_upload_state_fkey" FOREIGN KEY ("upload_state") REFERENCES "public"."photo_upload_states"("value");


--
-- Name: photos; Type: ROW SECURITY; Schema: public; Owner: postgres
--

ALTER TABLE "public"."photos" ENABLE ROW LEVEL SECURITY;

--
-- Name: photos photos_delete_own; Type: POLICY; Schema: public; Owner: postgres
--

CREATE POLICY "photos_delete_own" ON "public"."photos" FOR DELETE TO "authenticated" USING ((( SELECT "auth"."uid"() AS "uid") = "owner_id"));


--
-- Name: photos photos_insert_own; Type: POLICY; Schema: public; Owner: postgres
--

CREATE POLICY "photos_insert_own" ON "public"."photos" FOR INSERT TO "authenticated" WITH CHECK ((( SELECT "auth"."uid"() AS "uid") = "owner_id"));


--
-- Name: photos photos_select_own; Type: POLICY; Schema: public; Owner: postgres
--

CREATE POLICY "photos_select_own" ON "public"."photos" FOR SELECT TO "authenticated" USING ((( SELECT "auth"."uid"() AS "uid") = "owner_id"));


--
-- Name: photos photos_update_own; Type: POLICY; Schema: public; Owner: postgres
--

CREATE POLICY "photos_update_own" ON "public"."photos" FOR UPDATE TO "authenticated" USING ((( SELECT "auth"."uid"() AS "uid") = "owner_id")) WITH CHECK ((( SELECT "auth"."uid"() AS "uid") = "owner_id"));


--
-- Name: TABLE "photos"; Type: ACL; Schema: public; Owner: postgres
--

GRANT ALL ON TABLE "public"."photos" TO "service_role";
GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE "public"."photos" TO "authenticated";
