--
-- Name: plants; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE IF NOT EXISTS "public"."plants" (
    "id" "uuid" NOT NULL,
    "owner_id" "uuid" DEFAULT "auth"."uid"() NOT NULL,
    "display_name" "text" NOT NULL,
    "aliases" "text"[] NOT NULL,
    "scientific_name" "text",
    "authorship" "text",
    "gbif_key" integer,
    "notes" "text" NOT NULL,
    "notes_updated_at" timestamp with time zone,
    "cover_photo_id" "uuid",
    "created_at" timestamp with time zone NOT NULL,
    "updated_at" timestamp with time zone NOT NULL,
    "deleted_at" timestamp with time zone
);


ALTER TABLE "public"."plants" OWNER TO "postgres";

--
-- Name: TABLE "plants"; Type: COMMENT; Schema: public; Owner: postgres
--

COMMENT ON TABLE "public"."plants" IS 'A plant of the collection.
metadata: id=Ids.Plant_id';


--
-- Name: COLUMN "plants"."owner_id"; Type: COMMENT; Schema: public; Owner: postgres
--

COMMENT ON COLUMN "public"."plants"."owner_id" IS 'metadata: server_only';


--
-- Name: COLUMN "plants"."cover_photo_id"; Type: COMMENT; Schema: public; Owner: postgres
--

COMMENT ON COLUMN "public"."plants"."cover_photo_id" IS 'The photo shown on the plant''s card.
metadata: no_reverse';


--
-- Name: plants plants_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY "public"."plants"
    ADD CONSTRAINT "plants_pkey" PRIMARY KEY ("id");


--
-- Name: plants_cover_photo_id_idx; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX "plants_cover_photo_id_idx" ON "public"."plants" USING "btree" ("cover_photo_id");


--
-- Name: plants_owner_id_updated_at_idx; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX "plants_owner_id_updated_at_idx" ON "public"."plants" USING "btree" ("owner_id", "updated_at");


--
-- Name: plants plants_set_updated_at; Type: TRIGGER; Schema: public; Owner: postgres
--

CREATE OR REPLACE TRIGGER "plants_set_updated_at" BEFORE INSERT OR UPDATE ON "public"."plants" FOR EACH ROW EXECUTE FUNCTION "public"."set_updated_at"();


--
-- Name: plants plants_cover_photo_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY "public"."plants"
    ADD CONSTRAINT "plants_cover_photo_id_fkey" FOREIGN KEY ("cover_photo_id") REFERENCES "public"."photos"("id") ON DELETE SET NULL;


--
-- Name: plants plants_owner_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY "public"."plants"
    ADD CONSTRAINT "plants_owner_id_fkey" FOREIGN KEY ("owner_id") REFERENCES "auth"."users"("id") ON DELETE CASCADE;


--
-- Name: plants; Type: ROW SECURITY; Schema: public; Owner: postgres
--

ALTER TABLE "public"."plants" ENABLE ROW LEVEL SECURITY;

--
-- Name: plants plants_delete_own; Type: POLICY; Schema: public; Owner: postgres
--

CREATE POLICY "plants_delete_own" ON "public"."plants" FOR DELETE TO "authenticated" USING ((( SELECT "auth"."uid"() AS "uid") = "owner_id"));


--
-- Name: plants plants_insert_own; Type: POLICY; Schema: public; Owner: postgres
--

CREATE POLICY "plants_insert_own" ON "public"."plants" FOR INSERT TO "authenticated" WITH CHECK ((( SELECT "auth"."uid"() AS "uid") = "owner_id"));


--
-- Name: plants plants_select_own; Type: POLICY; Schema: public; Owner: postgres
--

CREATE POLICY "plants_select_own" ON "public"."plants" FOR SELECT TO "authenticated" USING ((( SELECT "auth"."uid"() AS "uid") = "owner_id"));


--
-- Name: plants plants_update_own; Type: POLICY; Schema: public; Owner: postgres
--

CREATE POLICY "plants_update_own" ON "public"."plants" FOR UPDATE TO "authenticated" USING ((( SELECT "auth"."uid"() AS "uid") = "owner_id")) WITH CHECK ((( SELECT "auth"."uid"() AS "uid") = "owner_id"));


--
-- Name: TABLE "plants"; Type: ACL; Schema: public; Owner: postgres
--

GRANT ALL ON TABLE "public"."plants" TO "service_role";
GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE "public"."plants" TO "authenticated";
