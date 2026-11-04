--
-- Name: reference; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE IF NOT EXISTS "public"."reference" (
    "id" "uuid" NOT NULL,
    "owner_id" "uuid" DEFAULT "auth"."uid"() NOT NULL,
    "plant_id" "uuid" NOT NULL,
    "source" "text" NOT NULL,
    "fetched_at" timestamp with time zone NOT NULL,
    "payload" "jsonb" NOT NULL,
    "status" "text" NOT NULL,
    "created_at" timestamp with time zone NOT NULL,
    "updated_at" timestamp with time zone NOT NULL,
    "deleted_at" timestamp with time zone
);


ALTER TABLE "public"."reference" OWNER TO "postgres";

--
-- Name: TABLE "reference"; Type: COMMENT; Schema: public; Owner: postgres
--

COMMENT ON TABLE "public"."reference" IS 'What one external source said about a plant.
metadata: id=Ids.Reference_id';


--
-- Name: COLUMN "reference"."owner_id"; Type: COMMENT; Schema: public; Owner: postgres
--

COMMENT ON COLUMN "public"."reference"."owner_id" IS 'metadata: server_only';


--
-- Name: reference reference_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY "public"."reference"
    ADD CONSTRAINT "reference_pkey" PRIMARY KEY ("id");


--
-- Name: reference reference_plant_id_source_key; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY "public"."reference"
    ADD CONSTRAINT "reference_plant_id_source_key" UNIQUE ("plant_id", "source");


--
-- Name: reference_owner_id_updated_at_idx; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX "reference_owner_id_updated_at_idx" ON "public"."reference" USING "btree" ("owner_id", "updated_at");


--
-- Name: reference reference_set_updated_at; Type: TRIGGER; Schema: public; Owner: postgres
--

CREATE OR REPLACE TRIGGER "reference_set_updated_at" BEFORE INSERT OR UPDATE ON "public"."reference" FOR EACH ROW EXECUTE FUNCTION "public"."set_updated_at"();


--
-- Name: reference reference_owner_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY "public"."reference"
    ADD CONSTRAINT "reference_owner_id_fkey" FOREIGN KEY ("owner_id") REFERENCES "auth"."users"("id") ON DELETE CASCADE;


--
-- Name: reference reference_plant_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY "public"."reference"
    ADD CONSTRAINT "reference_plant_id_fkey" FOREIGN KEY ("plant_id") REFERENCES "public"."plants"("id") ON DELETE CASCADE;


--
-- Name: reference reference_source_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY "public"."reference"
    ADD CONSTRAINT "reference_source_fkey" FOREIGN KEY ("source") REFERENCES "public"."reference_sources"("value");


--
-- Name: reference reference_status_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY "public"."reference"
    ADD CONSTRAINT "reference_status_fkey" FOREIGN KEY ("status") REFERENCES "public"."reference_statuses"("value");


--
-- Name: reference; Type: ROW SECURITY; Schema: public; Owner: postgres
--

ALTER TABLE "public"."reference" ENABLE ROW LEVEL SECURITY;

--
-- Name: reference reference_delete_own; Type: POLICY; Schema: public; Owner: postgres
--

CREATE POLICY "reference_delete_own" ON "public"."reference" FOR DELETE TO "authenticated" USING ((( SELECT "auth"."uid"() AS "uid") = "owner_id"));


--
-- Name: reference reference_insert_own; Type: POLICY; Schema: public; Owner: postgres
--

CREATE POLICY "reference_insert_own" ON "public"."reference" FOR INSERT TO "authenticated" WITH CHECK ((( SELECT "auth"."uid"() AS "uid") = "owner_id"));


--
-- Name: reference reference_select_own; Type: POLICY; Schema: public; Owner: postgres
--

CREATE POLICY "reference_select_own" ON "public"."reference" FOR SELECT TO "authenticated" USING ((( SELECT "auth"."uid"() AS "uid") = "owner_id"));


--
-- Name: reference reference_update_own; Type: POLICY; Schema: public; Owner: postgres
--

CREATE POLICY "reference_update_own" ON "public"."reference" FOR UPDATE TO "authenticated" USING ((( SELECT "auth"."uid"() AS "uid") = "owner_id")) WITH CHECK ((( SELECT "auth"."uid"() AS "uid") = "owner_id"));


--
-- Name: TABLE "reference"; Type: ACL; Schema: public; Owner: postgres
--

GRANT ALL ON TABLE "public"."reference" TO "service_role";
GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE "public"."reference" TO "authenticated";
