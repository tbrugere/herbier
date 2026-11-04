--
-- Name: plant_tags; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE IF NOT EXISTS "public"."plant_tags" (
    "id" "uuid" NOT NULL,
    "owner_id" "uuid" DEFAULT "auth"."uid"() NOT NULL,
    "plant_id" "uuid" NOT NULL,
    "tag_id" "uuid" NOT NULL,
    "created_at" timestamp with time zone NOT NULL,
    "updated_at" timestamp with time zone NOT NULL,
    "deleted_at" timestamp with time zone
);


ALTER TABLE "public"."plant_tags" OWNER TO "postgres";

--
-- Name: TABLE "plant_tags"; Type: COMMENT; Schema: public; Owner: postgres
--

COMMENT ON TABLE "public"."plant_tags" IS 'A tag on a plant.
metadata: id=Ids.Plant_tag_id';


--
-- Name: COLUMN "plant_tags"."owner_id"; Type: COMMENT; Schema: public; Owner: postgres
--

COMMENT ON COLUMN "public"."plant_tags"."owner_id" IS 'metadata: server_only';


--
-- Name: plant_tags plant_tags_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY "public"."plant_tags"
    ADD CONSTRAINT "plant_tags_pkey" PRIMARY KEY ("id");


--
-- Name: plant_tags plant_tags_plant_id_tag_id_key; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY "public"."plant_tags"
    ADD CONSTRAINT "plant_tags_plant_id_tag_id_key" UNIQUE ("plant_id", "tag_id");


--
-- Name: plant_tags_owner_id_updated_at_idx; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX "plant_tags_owner_id_updated_at_idx" ON "public"."plant_tags" USING "btree" ("owner_id", "updated_at");


--
-- Name: plant_tags_tag_id_idx; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX "plant_tags_tag_id_idx" ON "public"."plant_tags" USING "btree" ("tag_id");


--
-- Name: plant_tags plant_tags_set_updated_at; Type: TRIGGER; Schema: public; Owner: postgres
--

CREATE OR REPLACE TRIGGER "plant_tags_set_updated_at" BEFORE INSERT OR UPDATE ON "public"."plant_tags" FOR EACH ROW EXECUTE FUNCTION "public"."set_updated_at"();


--
-- Name: plant_tags plant_tags_owner_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY "public"."plant_tags"
    ADD CONSTRAINT "plant_tags_owner_id_fkey" FOREIGN KEY ("owner_id") REFERENCES "auth"."users"("id") ON DELETE CASCADE;


--
-- Name: plant_tags plant_tags_plant_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY "public"."plant_tags"
    ADD CONSTRAINT "plant_tags_plant_id_fkey" FOREIGN KEY ("plant_id") REFERENCES "public"."plants"("id") ON DELETE CASCADE;


--
-- Name: plant_tags plant_tags_tag_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY "public"."plant_tags"
    ADD CONSTRAINT "plant_tags_tag_id_fkey" FOREIGN KEY ("tag_id") REFERENCES "public"."tags"("id") ON DELETE CASCADE;


--
-- Name: plant_tags; Type: ROW SECURITY; Schema: public; Owner: postgres
--

ALTER TABLE "public"."plant_tags" ENABLE ROW LEVEL SECURITY;

--
-- Name: plant_tags plant_tags_delete_own; Type: POLICY; Schema: public; Owner: postgres
--

CREATE POLICY "plant_tags_delete_own" ON "public"."plant_tags" FOR DELETE TO "authenticated" USING ((( SELECT "auth"."uid"() AS "uid") = "owner_id"));


--
-- Name: plant_tags plant_tags_insert_own; Type: POLICY; Schema: public; Owner: postgres
--

CREATE POLICY "plant_tags_insert_own" ON "public"."plant_tags" FOR INSERT TO "authenticated" WITH CHECK ((( SELECT "auth"."uid"() AS "uid") = "owner_id"));


--
-- Name: plant_tags plant_tags_select_own; Type: POLICY; Schema: public; Owner: postgres
--

CREATE POLICY "plant_tags_select_own" ON "public"."plant_tags" FOR SELECT TO "authenticated" USING ((( SELECT "auth"."uid"() AS "uid") = "owner_id"));


--
-- Name: plant_tags plant_tags_update_own; Type: POLICY; Schema: public; Owner: postgres
--

CREATE POLICY "plant_tags_update_own" ON "public"."plant_tags" FOR UPDATE TO "authenticated" USING ((( SELECT "auth"."uid"() AS "uid") = "owner_id")) WITH CHECK ((( SELECT "auth"."uid"() AS "uid") = "owner_id"));


--
-- Name: TABLE "plant_tags"; Type: ACL; Schema: public; Owner: postgres
--

GRANT ALL ON TABLE "public"."plant_tags" TO "service_role";
GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE "public"."plant_tags" TO "authenticated";
