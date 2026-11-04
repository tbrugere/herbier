--
-- Name: observations; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE IF NOT EXISTS "public"."observations" (
    "id" "uuid" NOT NULL,
    "owner_id" "uuid" DEFAULT "auth"."uid"() NOT NULL,
    "plant_id" "uuid",
    "at" timestamp with time zone NOT NULL,
    "lat" double precision,
    "lon" double precision,
    "accuracy_m" double precision,
    "place_label" "text",
    "place_derived" "text",
    "note" "text",
    "loc" "extensions"."geography"(Point,4326),
    "created_at" timestamp with time zone NOT NULL,
    "updated_at" timestamp with time zone NOT NULL,
    "deleted_at" timestamp with time zone,
    CONSTRAINT "observations_accuracy_needs_position" CHECK ((("accuracy_m" IS NULL) OR ("lat" IS NOT NULL))),
    CONSTRAINT "observations_accuracy_nonnegative" CHECK (("accuracy_m" >= (0)::double precision)),
    CONSTRAINT "observations_lat_range" CHECK ((("lat" >= ('-90'::integer)::double precision) AND ("lat" <= (90)::double precision))),
    CONSTRAINT "observations_lon_range" CHECK ((("lon" >= ('-180'::integer)::double precision) AND ("lon" <= (180)::double precision))),
    CONSTRAINT "observations_position_both_or_neither" CHECK ((("lat" IS NULL) = ("lon" IS NULL)))
);


ALTER TABLE "public"."observations" OWNER TO "postgres";

--
-- Name: TABLE "observations"; Type: COMMENT; Schema: public; Owner: postgres
--

COMMENT ON TABLE "public"."observations" IS 'One sighting, optionally of a plant, with its position.
metadata: id=Ids.Observation_id';


--
-- Name: COLUMN "observations"."owner_id"; Type: COMMENT; Schema: public; Owner: postgres
--

COMMENT ON COLUMN "public"."observations"."owner_id" IS 'metadata: server_only';


--
-- Name: COLUMN "observations"."loc"; Type: COMMENT; Schema: public; Owner: postgres
--

COMMENT ON COLUMN "public"."observations"."loc" IS 'Set from lat and lon by a trigger.
metadata: server_only';


--
-- Name: observations observations_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY "public"."observations"
    ADD CONSTRAINT "observations_pkey" PRIMARY KEY ("id");


--
-- Name: observations_loc_idx; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX "observations_loc_idx" ON "public"."observations" USING "gist" ("loc");


--
-- Name: observations_owner_id_updated_at_idx; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX "observations_owner_id_updated_at_idx" ON "public"."observations" USING "btree" ("owner_id", "updated_at");


--
-- Name: observations_plant_id_idx; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX "observations_plant_id_idx" ON "public"."observations" USING "btree" ("plant_id");


--
-- Name: observations observations_set_loc; Type: TRIGGER; Schema: public; Owner: postgres
--

CREATE OR REPLACE TRIGGER "observations_set_loc" BEFORE INSERT OR UPDATE ON "public"."observations" FOR EACH ROW EXECUTE FUNCTION "public"."observations_set_loc"();


--
-- Name: observations observations_set_updated_at; Type: TRIGGER; Schema: public; Owner: postgres
--

CREATE OR REPLACE TRIGGER "observations_set_updated_at" BEFORE INSERT OR UPDATE ON "public"."observations" FOR EACH ROW EXECUTE FUNCTION "public"."set_updated_at"();


--
-- Name: observations observations_owner_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY "public"."observations"
    ADD CONSTRAINT "observations_owner_id_fkey" FOREIGN KEY ("owner_id") REFERENCES "auth"."users"("id") ON DELETE CASCADE;


--
-- Name: observations observations_plant_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY "public"."observations"
    ADD CONSTRAINT "observations_plant_id_fkey" FOREIGN KEY ("plant_id") REFERENCES "public"."plants"("id") ON DELETE CASCADE;


--
-- Name: observations; Type: ROW SECURITY; Schema: public; Owner: postgres
--

ALTER TABLE "public"."observations" ENABLE ROW LEVEL SECURITY;

--
-- Name: observations observations_delete_own; Type: POLICY; Schema: public; Owner: postgres
--

CREATE POLICY "observations_delete_own" ON "public"."observations" FOR DELETE TO "authenticated" USING ((( SELECT "auth"."uid"() AS "uid") = "owner_id"));


--
-- Name: observations observations_insert_own; Type: POLICY; Schema: public; Owner: postgres
--

CREATE POLICY "observations_insert_own" ON "public"."observations" FOR INSERT TO "authenticated" WITH CHECK ((( SELECT "auth"."uid"() AS "uid") = "owner_id"));


--
-- Name: observations observations_select_own; Type: POLICY; Schema: public; Owner: postgres
--

CREATE POLICY "observations_select_own" ON "public"."observations" FOR SELECT TO "authenticated" USING ((( SELECT "auth"."uid"() AS "uid") = "owner_id"));


--
-- Name: observations observations_update_own; Type: POLICY; Schema: public; Owner: postgres
--

CREATE POLICY "observations_update_own" ON "public"."observations" FOR UPDATE TO "authenticated" USING ((( SELECT "auth"."uid"() AS "uid") = "owner_id")) WITH CHECK ((( SELECT "auth"."uid"() AS "uid") = "owner_id"));


--
-- Name: TABLE "observations"; Type: ACL; Schema: public; Owner: postgres
--

GRANT ALL ON TABLE "public"."observations" TO "service_role";
GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE "public"."observations" TO "authenticated";
