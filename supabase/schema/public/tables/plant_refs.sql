--
-- Name: plant_refs; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE IF NOT EXISTS "public"."plant_refs" (
    "id" "uuid" NOT NULL,
    "owner_id" "uuid" DEFAULT "auth"."uid"() NOT NULL,
    "plant_id" "uuid" NOT NULL,
    "source" "text" NOT NULL,
    "external_id" "text" NOT NULL,
    "url" "text" NOT NULL,
    "created_at" timestamp with time zone NOT NULL,
    "updated_at" timestamp with time zone NOT NULL,
    "deleted_at" timestamp with time zone
);


ALTER TABLE "public"."plant_refs" OWNER TO "postgres";

--
-- Name: TABLE "plant_refs"; Type: COMMENT; Schema: public; Owner: postgres
--

COMMENT ON TABLE "public"."plant_refs" IS 'The plant''s identifier at one external source.
metadata: id=Ids.Plant_ref_id';


--
-- Name: COLUMN "plant_refs"."owner_id"; Type: COMMENT; Schema: public; Owner: postgres
--

COMMENT ON COLUMN "public"."plant_refs"."owner_id" IS 'metadata: server_only';


--
-- Name: plant_refs plant_refs_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY "public"."plant_refs"
    ADD CONSTRAINT "plant_refs_pkey" PRIMARY KEY ("id");


--
-- Name: plant_refs plant_refs_plant_id_source_key; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY "public"."plant_refs"
    ADD CONSTRAINT "plant_refs_plant_id_source_key" UNIQUE ("plant_id", "source");


--
-- Name: plant_refs_owner_id_updated_at_idx; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX "plant_refs_owner_id_updated_at_idx" ON "public"."plant_refs" USING "btree" ("owner_id", "updated_at");


--
-- Name: plant_refs plant_refs_set_updated_at; Type: TRIGGER; Schema: public; Owner: postgres
--

CREATE OR REPLACE TRIGGER "plant_refs_set_updated_at" BEFORE INSERT OR UPDATE ON "public"."plant_refs" FOR EACH ROW EXECUTE FUNCTION "public"."set_updated_at"();


--
-- Name: plant_refs plant_refs_owner_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY "public"."plant_refs"
    ADD CONSTRAINT "plant_refs_owner_id_fkey" FOREIGN KEY ("owner_id") REFERENCES "auth"."users"("id") ON DELETE CASCADE;


--
-- Name: plant_refs plant_refs_plant_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY "public"."plant_refs"
    ADD CONSTRAINT "plant_refs_plant_id_fkey" FOREIGN KEY ("plant_id") REFERENCES "public"."plants"("id") ON DELETE CASCADE;


--
-- Name: plant_refs plant_refs_source_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY "public"."plant_refs"
    ADD CONSTRAINT "plant_refs_source_fkey" FOREIGN KEY ("source") REFERENCES "public"."reference_sources"("value");


--
-- Name: plant_refs; Type: ROW SECURITY; Schema: public; Owner: postgres
--

ALTER TABLE "public"."plant_refs" ENABLE ROW LEVEL SECURITY;

--
-- Name: plant_refs plant_refs_delete_own; Type: POLICY; Schema: public; Owner: postgres
--

CREATE POLICY "plant_refs_delete_own" ON "public"."plant_refs" FOR DELETE TO "authenticated" USING ((( SELECT "auth"."uid"() AS "uid") = "owner_id"));


--
-- Name: plant_refs plant_refs_insert_own; Type: POLICY; Schema: public; Owner: postgres
--

CREATE POLICY "plant_refs_insert_own" ON "public"."plant_refs" FOR INSERT TO "authenticated" WITH CHECK ((( SELECT "auth"."uid"() AS "uid") = "owner_id"));


--
-- Name: plant_refs plant_refs_select_own; Type: POLICY; Schema: public; Owner: postgres
--

CREATE POLICY "plant_refs_select_own" ON "public"."plant_refs" FOR SELECT TO "authenticated" USING ((( SELECT "auth"."uid"() AS "uid") = "owner_id"));


--
-- Name: plant_refs plant_refs_update_own; Type: POLICY; Schema: public; Owner: postgres
--

CREATE POLICY "plant_refs_update_own" ON "public"."plant_refs" FOR UPDATE TO "authenticated" USING ((( SELECT "auth"."uid"() AS "uid") = "owner_id")) WITH CHECK ((( SELECT "auth"."uid"() AS "uid") = "owner_id"));


--
-- Name: TABLE "plant_refs"; Type: ACL; Schema: public; Owner: postgres
--

GRANT ALL ON TABLE "public"."plant_refs" TO "service_role";
GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE "public"."plant_refs" TO "authenticated";
