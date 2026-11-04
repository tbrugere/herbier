--
-- Name: tags; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE IF NOT EXISTS "public"."tags" (
    "id" "uuid" NOT NULL,
    "owner_id" "uuid" DEFAULT "auth"."uid"() NOT NULL,
    "name" "text" NOT NULL,
    "created_at" timestamp with time zone NOT NULL,
    "updated_at" timestamp with time zone NOT NULL,
    "deleted_at" timestamp with time zone
);


ALTER TABLE "public"."tags" OWNER TO "postgres";

--
-- Name: TABLE "tags"; Type: COMMENT; Schema: public; Owner: postgres
--

COMMENT ON TABLE "public"."tags" IS 'A user-defined tag.
metadata: id=Ids.Tag_id';


--
-- Name: COLUMN "tags"."owner_id"; Type: COMMENT; Schema: public; Owner: postgres
--

COMMENT ON COLUMN "public"."tags"."owner_id" IS 'metadata: server_only';


--
-- Name: tags tags_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY "public"."tags"
    ADD CONSTRAINT "tags_pkey" PRIMARY KEY ("id");


--
-- Name: tags_owner_id_updated_at_idx; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX "tags_owner_id_updated_at_idx" ON "public"."tags" USING "btree" ("owner_id", "updated_at");


--
-- Name: tags tags_set_updated_at; Type: TRIGGER; Schema: public; Owner: postgres
--

CREATE OR REPLACE TRIGGER "tags_set_updated_at" BEFORE INSERT OR UPDATE ON "public"."tags" FOR EACH ROW EXECUTE FUNCTION "public"."set_updated_at"();


--
-- Name: tags tags_owner_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY "public"."tags"
    ADD CONSTRAINT "tags_owner_id_fkey" FOREIGN KEY ("owner_id") REFERENCES "auth"."users"("id") ON DELETE CASCADE;


--
-- Name: tags; Type: ROW SECURITY; Schema: public; Owner: postgres
--

ALTER TABLE "public"."tags" ENABLE ROW LEVEL SECURITY;

--
-- Name: tags tags_delete_own; Type: POLICY; Schema: public; Owner: postgres
--

CREATE POLICY "tags_delete_own" ON "public"."tags" FOR DELETE TO "authenticated" USING ((( SELECT "auth"."uid"() AS "uid") = "owner_id"));


--
-- Name: tags tags_insert_own; Type: POLICY; Schema: public; Owner: postgres
--

CREATE POLICY "tags_insert_own" ON "public"."tags" FOR INSERT TO "authenticated" WITH CHECK ((( SELECT "auth"."uid"() AS "uid") = "owner_id"));


--
-- Name: tags tags_select_own; Type: POLICY; Schema: public; Owner: postgres
--

CREATE POLICY "tags_select_own" ON "public"."tags" FOR SELECT TO "authenticated" USING ((( SELECT "auth"."uid"() AS "uid") = "owner_id"));


--
-- Name: tags tags_update_own; Type: POLICY; Schema: public; Owner: postgres
--

CREATE POLICY "tags_update_own" ON "public"."tags" FOR UPDATE TO "authenticated" USING ((( SELECT "auth"."uid"() AS "uid") = "owner_id")) WITH CHECK ((( SELECT "auth"."uid"() AS "uid") = "owner_id"));


--
-- Name: TABLE "tags"; Type: ACL; Schema: public; Owner: postgres
--

GRANT ALL ON TABLE "public"."tags" TO "service_role";
GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE "public"."tags" TO "authenticated";
