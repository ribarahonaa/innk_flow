\restrict cSrLNLaNA3LiyaBJ8ywYyM7U6gEcIjqfBtpjz3qVkrz1cHGeeheNbLMrdPhjyu1

-- Dumped from database version 17.9 (Debian 17.9-1.pgdg12+1)
-- Dumped by pg_dump version 17.11 (Debian 17.11-1.pgdg12+2)

SET statement_timeout = 0;
SET lock_timeout = 0;
SET idle_in_transaction_session_timeout = 0;
SET transaction_timeout = 0;
SET client_encoding = 'UTF8';
SET standard_conforming_strings = on;
SELECT pg_catalog.set_config('search_path', '', false);
SET check_function_bodies = false;
SET xmloption = content;
SET client_min_messages = warning;
SET row_security = off;

--
-- Name: pgcrypto; Type: EXTENSION; Schema: -; Owner: -
--

CREATE EXTENSION IF NOT EXISTS pgcrypto WITH SCHEMA public;


--
-- Name: EXTENSION pgcrypto; Type: COMMENT; Schema: -; Owner: -
--

COMMENT ON EXTENSION pgcrypto IS 'cryptographic functions';


--
-- Name: uuid_generate_v7(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.uuid_generate_v7() RETURNS uuid
    LANGUAGE plpgsql
    AS $$
DECLARE
  unix_ts_ms bytea;
  uuid_bytes bytea;
BEGIN
  unix_ts_ms := substring(
    int8send((extract(epoch from clock_timestamp()) * 1000)::bigint) from 3
  );
  uuid_bytes := unix_ts_ms || gen_random_bytes(10);
  -- nibble alto del byte 6 = version (7)
  uuid_bytes := set_byte(uuid_bytes, 6, ((get_byte(uuid_bytes, 6) & 15) | 112));
  -- dos bits altos del byte 8 = variant (RFC 4122)
  uuid_bytes := set_byte(uuid_bytes, 8, ((get_byte(uuid_bytes, 8) & 63) | 128));
  RETURN encode(uuid_bytes, 'hex')::uuid;
END
$$;


SET default_tablespace = '';

SET default_table_access_method = heap;

--
-- Name: active_storage_attachments; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.active_storage_attachments (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    name character varying NOT NULL,
    record_type character varying NOT NULL,
    record_id uuid NOT NULL,
    blob_id uuid NOT NULL,
    created_at timestamp(6) without time zone NOT NULL
);


--
-- Name: active_storage_blobs; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.active_storage_blobs (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    key character varying NOT NULL,
    filename character varying NOT NULL,
    content_type character varying,
    metadata text,
    service_name character varying NOT NULL,
    byte_size bigint NOT NULL,
    checksum character varying,
    created_at timestamp(6) without time zone NOT NULL
);


--
-- Name: active_storage_variant_records; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.active_storage_variant_records (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    blob_id uuid NOT NULL,
    variation_digest character varying NOT NULL
);


--
-- Name: ai_runs; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.ai_runs (
    id uuid DEFAULT public.uuid_generate_v7() NOT NULL,
    company_id uuid NOT NULL,
    challenge_id uuid,
    challenge_step_id uuid,
    idea_id uuid,
    requested_by_id uuid,
    purpose character varying NOT NULL,
    mode character varying NOT NULL,
    status character varying DEFAULT 'queued'::character varying NOT NULL,
    prompt jsonb DEFAULT '{}'::jsonb NOT NULL,
    response jsonb,
    provider character varying,
    model character varying,
    tokens_in integer,
    tokens_out integer,
    latency_ms integer,
    error text,
    idempotency_key character varying,
    redacted_at timestamp(6) without time zone,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL,
    CONSTRAINT ai_runs_mode_check CHECK (((mode)::text = ANY (ARRAY[('ai_assisted'::character varying)::text, ('ai_auto'::character varying)::text]))),
    CONSTRAINT ai_runs_purpose_check CHECK (((purpose)::text = ANY ((ARRAY['propose_pipeline'::character varying, 'suggest_form_fields'::character varying, 'suggest_criteria'::character varying, 'generate_ideas'::character varying, 'coauthor_field'::character varying, 'detect_duplicates'::character varying, 'suggest_feedback'::character varying, 'evaluate_idea'::character varying, 'decide_verdicts'::character varying, 'summarize_challenge'::character varying])::text[]))),
    CONSTRAINT ai_runs_status_check CHECK (((status)::text = ANY (ARRAY[('queued'::character varying)::text, ('running'::character varying)::text, ('succeeded'::character varying)::text, ('failed'::character varying)::text])))
);


--
-- Name: ai_suggestions; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.ai_suggestions (
    id uuid DEFAULT public.uuid_generate_v7() NOT NULL,
    company_id uuid NOT NULL,
    ai_run_id uuid NOT NULL,
    challenge_id uuid,
    challenge_step_id uuid,
    idea_id uuid,
    criteria_set_id uuid,
    payload jsonb DEFAULT '{}'::jsonb NOT NULL,
    status character varying DEFAULT 'pending'::character varying NOT NULL,
    reviewed_by_id uuid,
    reviewed_at timestamp(6) without time zone,
    auto_accepted_at timestamp(6) without time zone,
    review_note text,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL,
    CONSTRAINT ai_suggestions_single_target_check CHECK (((((((challenge_id IS NOT NULL))::integer + ((challenge_step_id IS NOT NULL))::integer) + ((idea_id IS NOT NULL))::integer) + ((criteria_set_id IS NOT NULL))::integer) = 1)),
    CONSTRAINT ai_suggestions_status_check CHECK (((status)::text = ANY (ARRAY[('pending'::character varying)::text, ('accepted'::character varying)::text, ('edited'::character varying)::text, ('rejected'::character varying)::text])))
);


--
-- Name: ar_internal_metadata; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.ar_internal_metadata (
    key character varying NOT NULL,
    value character varying,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL
);


--
-- Name: assessment_scores; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.assessment_scores (
    id uuid DEFAULT public.uuid_generate_v7() NOT NULL,
    company_id uuid NOT NULL,
    assessment_id uuid NOT NULL,
    criterion_id uuid,
    criterion_key character varying NOT NULL,
    weight_used numeric(8,6) DEFAULT 0.0 NOT NULL,
    raw_value character varying,
    numeric_value numeric(12,4),
    normalized_value numeric(10,6),
    comment text,
    error text,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL
);


--
-- Name: assessments; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.assessments (
    id uuid DEFAULT public.uuid_generate_v7() NOT NULL,
    company_id uuid NOT NULL,
    challenge_step_id uuid NOT NULL,
    idea_id uuid NOT NULL,
    idea_version_id uuid NOT NULL,
    evaluator_id uuid,
    actor_type character varying DEFAULT 'human'::character varying NOT NULL,
    status character varying DEFAULT 'pending'::character varying NOT NULL,
    ai_run_id uuid,
    overall_comment text,
    normalized_score numeric(10,6),
    raw_score numeric(10,4),
    submitted_at timestamp(6) without time zone,
    superseded_at timestamp(6) without time zone,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL,
    CONSTRAINT assessments_actor_type_check CHECK (((actor_type)::text = ANY (ARRAY[('human'::character varying)::text, ('ai'::character varying)::text]))),
    CONSTRAINT assessments_status_check CHECK (((status)::text = ANY (ARRAY[('pending'::character varying)::text, ('submitted'::character varying)::text])))
);


--
-- Name: challenge_gestores; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.challenge_gestores (
    id uuid DEFAULT public.uuid_generate_v7() NOT NULL,
    company_id uuid NOT NULL,
    challenge_id uuid NOT NULL,
    user_id uuid NOT NULL,
    assigned_at timestamp(6) without time zone DEFAULT now() NOT NULL,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL
);


--
-- Name: challenge_steps; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.challenge_steps (
    id uuid DEFAULT public.uuid_generate_v7() NOT NULL,
    company_id uuid NOT NULL,
    challenge_id uuid NOT NULL,
    slug character varying NOT NULL,
    "position" numeric(20,10) NOT NULL,
    kind character varying NOT NULL,
    name character varying NOT NULL,
    status character varying DEFAULT 'pending'::character varying NOT NULL,
    ai_mode character varying,
    source_step_id uuid,
    config jsonb DEFAULT '{}'::jsonb NOT NULL,
    resolved_config jsonb,
    lock_version integer DEFAULT 0 NOT NULL,
    started_at timestamp(6) without time zone,
    completed_at timestamp(6) without time zone,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL,
    criteria_set_id uuid,
    CONSTRAINT challenge_steps_ai_mode_check CHECK (((ai_mode IS NULL) OR ((ai_mode)::text = ANY (ARRAY[('human'::character varying)::text, ('ai_assisted'::character varying)::text, ('ai_auto'::character varying)::text])))),
    CONSTRAINT challenge_steps_kind_check CHECK (((kind)::text = ANY (ARRAY[('ideation'::character varying)::text, ('evolution'::character varying)::text, ('evaluation'::character varying)::text, ('selection'::character varying)::text, ('reporting'::character varying)::text]))),
    CONSTRAINT challenge_steps_status_check CHECK (((status)::text = ANY (ARRAY[('pending'::character varying)::text, ('activating'::character varying)::text, ('active'::character varying)::text, ('completed'::character varying)::text, ('skipped'::character varying)::text])))
);


--
-- Name: challenges; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.challenges (
    id uuid DEFAULT public.uuid_generate_v7() NOT NULL,
    company_id uuid NOT NULL,
    slug character varying NOT NULL,
    name character varying NOT NULL,
    brief text,
    status character varying DEFAULT 'draft'::character varying NOT NULL,
    ai_default_mode character varying DEFAULT 'human'::character varying NOT NULL,
    started_at timestamp(6) without time zone,
    closed_at timestamp(6) without time zone,
    lock_version integer DEFAULT 0 NOT NULL,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL,
    CONSTRAINT challenges_ai_default_mode_check CHECK (((ai_default_mode)::text = ANY (ARRAY[('human'::character varying)::text, ('ai_assisted'::character varying)::text, ('ai_auto'::character varying)::text]))),
    CONSTRAINT challenges_status_check CHECK (((status)::text = ANY (ARRAY[('draft'::character varying)::text, ('running'::character varying)::text, ('closed'::character varying)::text, ('archived'::character varying)::text])))
);


--
-- Name: companies; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.companies (
    id uuid DEFAULT public.uuid_generate_v7() NOT NULL,
    name character varying NOT NULL,
    slug character varying NOT NULL,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL
);


--
-- Name: criteria; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.criteria (
    id uuid DEFAULT public.uuid_generate_v7() NOT NULL,
    company_id uuid NOT NULL,
    criteria_set_id uuid NOT NULL,
    key character varying NOT NULL,
    name character varying NOT NULL,
    description text,
    weight numeric(8,6) DEFAULT 0.0 NOT NULL,
    scale_type character varying DEFAULT 'numeric'::character varying NOT NULL,
    scale_config jsonb DEFAULT '{}'::jsonb NOT NULL,
    "position" integer DEFAULT 0 NOT NULL,
    active boolean DEFAULT true NOT NULL,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL,
    source character varying DEFAULT 'manual'::character varying NOT NULL,
    source_config jsonb DEFAULT '{}'::jsonb NOT NULL,
    CONSTRAINT criteria_automatic_needs_check CHECK ((((source)::text <> 'automatic'::text) OR (source_config ? 'check'::text))),
    CONSTRAINT criteria_scale_type_check CHECK (((scale_type)::text = ANY (ARRAY[('numeric'::character varying)::text, ('letter'::character varying)::text, ('rubric'::character varying)::text, ('boolean'::character varying)::text]))),
    CONSTRAINT criteria_source_check CHECK (((source)::text = ANY (ARRAY[('manual'::character varying)::text, ('automatic'::character varying)::text, ('ai'::character varying)::text, ('formula'::character varying)::text])))
);


--
-- Name: criteria_sets; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.criteria_sets (
    id uuid DEFAULT public.uuid_generate_v7() NOT NULL,
    company_id uuid NOT NULL,
    name character varying NOT NULL,
    description text,
    scope character varying DEFAULT 'library'::character varying NOT NULL,
    owner_step_id uuid,
    status character varying DEFAULT 'draft'::character varying NOT NULL,
    lock_version integer DEFAULT 0 NOT NULL,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL,
    family_id uuid NOT NULL,
    version integer DEFAULT 1 NOT NULL,
    superseded_at timestamp(6) without time zone,
    CONSTRAINT criteria_sets_scope_check CHECK (((scope)::text = ANY (ARRAY[('library'::character varying)::text, ('inline'::character varying)::text]))),
    CONSTRAINT criteria_sets_status_check CHECK (((status)::text = ANY (ARRAY[('draft'::character varying)::text, ('valid'::character varying)::text, ('invalid'::character varying)::text])))
);


--
-- Name: feedback_items; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.feedback_items (
    id uuid DEFAULT public.uuid_generate_v7() NOT NULL,
    company_id uuid NOT NULL,
    challenge_step_id uuid NOT NULL,
    idea_id uuid NOT NULL,
    idea_version_id uuid NOT NULL,
    author_id uuid,
    actor_type character varying DEFAULT 'human'::character varying NOT NULL,
    kind character varying DEFAULT 'suggestion'::character varying NOT NULL,
    body text NOT NULL,
    addressed boolean DEFAULT false NOT NULL,
    addressed_by_version_id uuid,
    ai_run_id uuid,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL,
    resolution character varying,
    resolution_note text,
    resolved_at timestamp(6) without time zone,
    resolved_by_id uuid,
    CONSTRAINT feedback_items_actor_type_check CHECK (((actor_type)::text = ANY (ARRAY[('human'::character varying)::text, ('ai'::character varying)::text]))),
    CONSTRAINT feedback_items_kind_check CHECK (((kind)::text = ANY (ARRAY[('suggestion'::character varying)::text, ('question'::character varying)::text, ('issue'::character varying)::text]))),
    CONSTRAINT feedback_items_resolution_check CHECK (((resolution IS NULL) OR ((resolution)::text = ANY (ARRAY[('answered'::character varying)::text, ('acknowledged'::character varying)::text, ('dismissed'::character varying)::text]))))
);


--
-- Name: form_fields; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.form_fields (
    id uuid DEFAULT public.uuid_generate_v7() NOT NULL,
    company_id uuid NOT NULL,
    challenge_step_id uuid NOT NULL,
    key character varying NOT NULL,
    label character varying NOT NULL,
    hint text,
    field_type character varying DEFAULT 'text'::character varying NOT NULL,
    required boolean DEFAULT false NOT NULL,
    "position" integer DEFAULT 0 NOT NULL,
    config jsonb DEFAULT '{}'::jsonb NOT NULL,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL,
    CONSTRAINT form_fields_field_type_check CHECK (((field_type)::text = ANY (ARRAY[('text'::character varying)::text, ('textarea'::character varying)::text, ('number'::character varying)::text, ('date'::character varying)::text, ('select'::character varying)::text, ('multi_select'::character varying)::text, ('file'::character varying)::text, ('rich_text'::character varying)::text])))
);


--
-- Name: idea_attachments; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.idea_attachments (
    id uuid DEFAULT public.uuid_generate_v7() NOT NULL,
    company_id uuid NOT NULL,
    idea_version_id uuid NOT NULL,
    field_key character varying NOT NULL,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL
);


--
-- Name: idea_contributors; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.idea_contributors (
    id uuid DEFAULT public.uuid_generate_v7() NOT NULL,
    company_id uuid NOT NULL,
    idea_id uuid NOT NULL,
    user_id uuid NOT NULL,
    role character varying DEFAULT 'contributor'::character varying NOT NULL,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL
);


--
-- Name: idea_versions; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.idea_versions (
    id uuid DEFAULT public.uuid_generate_v7() NOT NULL,
    company_id uuid NOT NULL,
    idea_id uuid NOT NULL,
    number integer NOT NULL,
    title character varying,
    payload jsonb DEFAULT '{}'::jsonb NOT NULL,
    created_by_id uuid,
    actor_type character varying DEFAULT 'human'::character varying NOT NULL,
    source_step_id uuid,
    change_note text,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL,
    CONSTRAINT idea_versions_actor_type_check CHECK (((actor_type)::text = ANY (ARRAY[('human'::character varying)::text, ('ai'::character varying)::text])))
);


--
-- Name: ideas; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.ideas (
    id uuid DEFAULT public.uuid_generate_v7() NOT NULL,
    company_id uuid NOT NULL,
    challenge_id uuid NOT NULL,
    author_id uuid NOT NULL,
    current_version_id uuid,
    status character varying DEFAULT 'draft'::character varying NOT NULL,
    origin character varying DEFAULT 'human'::character varying NOT NULL,
    eliminated_at_step_id uuid,
    submitted_at timestamp(6) without time zone,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL,
    CONSTRAINT ideas_origin_check CHECK (((origin)::text = ANY (ARRAY[('human'::character varying)::text, ('ai'::character varying)::text]))),
    CONSTRAINT ideas_status_check CHECK (((status)::text = ANY (ARRAY[('draft'::character varying)::text, ('active'::character varying)::text, ('eliminated'::character varying)::text, ('withdrawn'::character varying)::text])))
);


--
-- Name: identities; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.identities (
    id uuid DEFAULT public.uuid_generate_v7() NOT NULL,
    user_id uuid NOT NULL,
    provider character varying DEFAULT 'password'::character varying NOT NULL,
    uid character varying NOT NULL,
    data jsonb DEFAULT '{}'::jsonb NOT NULL,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL
);


--
-- Name: memberships; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.memberships (
    id uuid DEFAULT public.uuid_generate_v7() NOT NULL,
    company_id uuid NOT NULL,
    user_id uuid NOT NULL,
    role character varying DEFAULT 'participant'::character varying NOT NULL,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL,
    CONSTRAINT memberships_role_check CHECK (((role)::text = ANY ((ARRAY['admin'::character varying, 'gestor'::character varying, 'evaluator'::character varying, 'participant'::character varying])::text[])))
);


--
-- Name: notifications; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.notifications (
    id uuid DEFAULT public.uuid_generate_v7() NOT NULL,
    company_id uuid NOT NULL,
    user_id uuid NOT NULL,
    kind character varying NOT NULL,
    challenge_id uuid,
    challenge_step_id uuid,
    idea_id uuid,
    payload jsonb DEFAULT '{}'::jsonb NOT NULL,
    read_at timestamp(6) without time zone,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL
);


--
-- Name: reports; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.reports (
    id uuid DEFAULT public.uuid_generate_v7() NOT NULL,
    company_id uuid NOT NULL,
    challenge_step_id uuid NOT NULL,
    kind character varying DEFAULT 'snapshot'::character varying NOT NULL,
    format character varying DEFAULT 'dashboard'::character varying NOT NULL,
    status character varying DEFAULT 'pending'::character varying NOT NULL,
    scope jsonb DEFAULT '{}'::jsonb NOT NULL,
    data jsonb DEFAULT '{}'::jsonb NOT NULL,
    row_count integer,
    generated_at timestamp(6) without time zone,
    error text,
    requested_by_id uuid,
    ai_run_id uuid,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL,
    CONSTRAINT reports_format_check CHECK (((format)::text = ANY (ARRAY[('dashboard'::character varying)::text, ('xlsx'::character varying)::text, ('pdf'::character varying)::text]))),
    CONSTRAINT reports_kind_check CHECK (((kind)::text = ANY (ARRAY[('funnel'::character varying)::text, ('ranking'::character varying)::text, ('snapshot'::character varying)::text, ('narrative'::character varying)::text]))),
    CONSTRAINT reports_status_check CHECK (((status)::text = ANY (ARRAY[('pending'::character varying)::text, ('ready'::character varying)::text, ('failed'::character varying)::text])))
);


--
-- Name: schema_migrations; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.schema_migrations (
    version character varying NOT NULL
);


--
-- Name: selection_decisions; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.selection_decisions (
    id uuid DEFAULT public.uuid_generate_v7() NOT NULL,
    company_id uuid NOT NULL,
    challenge_step_id uuid NOT NULL,
    idea_id uuid NOT NULL,
    idea_version_id uuid NOT NULL,
    outcome character varying NOT NULL,
    rank integer,
    score numeric(10,6),
    decided_by_id uuid,
    actor_type character varying DEFAULT 'human'::character varying NOT NULL,
    reason text,
    decided_at timestamp(6) without time zone NOT NULL,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL,
    CONSTRAINT selection_decisions_actor_type_check CHECK (((actor_type)::text = ANY (ARRAY[('human'::character varying)::text, ('ai'::character varying)::text]))),
    CONSTRAINT selection_decisions_outcome_check CHECK (((outcome)::text = ANY (ARRAY[('advance'::character varying)::text, ('eliminate'::character varying)::text, ('reinstate'::character varying)::text])))
);


--
-- Name: selection_verdicts; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.selection_verdicts (
    id uuid DEFAULT public.uuid_generate_v7() NOT NULL,
    company_id uuid NOT NULL,
    challenge_step_id uuid NOT NULL,
    idea_id uuid NOT NULL,
    idea_version_id uuid NOT NULL,
    criterion_key character varying NOT NULL,
    criterion_id uuid,
    passed boolean NOT NULL,
    actor_type character varying DEFAULT 'human'::character varying NOT NULL,
    decided_by_id uuid,
    ai_run_id uuid,
    note text,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL,
    CONSTRAINT selection_verdicts_actor_type_check CHECK (((actor_type)::text = ANY (ARRAY[('human'::character varying)::text, ('ai'::character varying)::text])))
);


--
-- Name: sessions; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.sessions (
    id uuid DEFAULT public.uuid_generate_v7() NOT NULL,
    user_id uuid NOT NULL,
    company_id uuid,
    token character varying NOT NULL,
    user_agent character varying,
    ip_address character varying,
    last_seen_at timestamp(6) without time zone,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL
);


--
-- Name: step_assignments; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.step_assignments (
    id uuid DEFAULT public.uuid_generate_v7() NOT NULL,
    company_id uuid NOT NULL,
    challenge_step_id uuid NOT NULL,
    user_id uuid NOT NULL,
    role character varying DEFAULT 'evaluator'::character varying NOT NULL,
    weight numeric(8,6),
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL,
    CONSTRAINT step_assignments_role_check CHECK (((role)::text = ANY (ARRAY[('evaluator'::character varying)::text, ('jury'::character varying)::text])))
);


--
-- Name: step_entries; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.step_entries (
    id uuid DEFAULT public.uuid_generate_v7() NOT NULL,
    company_id uuid NOT NULL,
    challenge_step_id uuid NOT NULL,
    idea_id uuid NOT NULL,
    status character varying DEFAULT 'pending'::character varying NOT NULL,
    input_version_id uuid,
    output_version_id uuid,
    result jsonb DEFAULT '{}'::jsonb NOT NULL,
    entered_at timestamp(6) without time zone,
    resolved_at timestamp(6) without time zone,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL,
    CONSTRAINT step_entries_status_check CHECK (((status)::text = ANY (ARRAY[('pending'::character varying)::text, ('in_progress'::character varying)::text, ('done'::character varying)::text, ('advanced'::character varying)::text, ('eliminated'::character varying)::text])))
);


--
-- Name: users; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.users (
    id uuid DEFAULT public.uuid_generate_v7() NOT NULL,
    email character varying NOT NULL,
    name character varying NOT NULL,
    password_digest character varying,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL
);


--
-- Name: active_storage_attachments active_storage_attachments_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.active_storage_attachments
    ADD CONSTRAINT active_storage_attachments_pkey PRIMARY KEY (id);


--
-- Name: active_storage_blobs active_storage_blobs_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.active_storage_blobs
    ADD CONSTRAINT active_storage_blobs_pkey PRIMARY KEY (id);


--
-- Name: active_storage_variant_records active_storage_variant_records_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.active_storage_variant_records
    ADD CONSTRAINT active_storage_variant_records_pkey PRIMARY KEY (id);


--
-- Name: ai_runs ai_runs_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.ai_runs
    ADD CONSTRAINT ai_runs_pkey PRIMARY KEY (id);


--
-- Name: ai_runs ai_runs_tenant_uniq; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.ai_runs
    ADD CONSTRAINT ai_runs_tenant_uniq UNIQUE (id, company_id);


--
-- Name: ai_suggestions ai_suggestions_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.ai_suggestions
    ADD CONSTRAINT ai_suggestions_pkey PRIMARY KEY (id);


--
-- Name: ai_suggestions ai_suggestions_tenant_uniq; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.ai_suggestions
    ADD CONSTRAINT ai_suggestions_tenant_uniq UNIQUE (id, company_id);


--
-- Name: ar_internal_metadata ar_internal_metadata_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.ar_internal_metadata
    ADD CONSTRAINT ar_internal_metadata_pkey PRIMARY KEY (key);


--
-- Name: assessment_scores assessment_scores_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.assessment_scores
    ADD CONSTRAINT assessment_scores_pkey PRIMARY KEY (id);


--
-- Name: assessment_scores assessment_scores_tenant_uniq; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.assessment_scores
    ADD CONSTRAINT assessment_scores_tenant_uniq UNIQUE (id, company_id);


--
-- Name: assessments assessments_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.assessments
    ADD CONSTRAINT assessments_pkey PRIMARY KEY (id);


--
-- Name: assessments assessments_tenant_uniq; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.assessments
    ADD CONSTRAINT assessments_tenant_uniq UNIQUE (id, company_id);


--
-- Name: challenge_gestores challenge_gestores_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.challenge_gestores
    ADD CONSTRAINT challenge_gestores_pkey PRIMARY KEY (id);


--
-- Name: challenge_gestores challenge_gestores_tenant_uniq; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.challenge_gestores
    ADD CONSTRAINT challenge_gestores_tenant_uniq UNIQUE (id, company_id);


--
-- Name: challenge_steps challenge_steps_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.challenge_steps
    ADD CONSTRAINT challenge_steps_pkey PRIMARY KEY (id);


--
-- Name: challenge_steps challenge_steps_position_unique; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.challenge_steps
    ADD CONSTRAINT challenge_steps_position_unique UNIQUE (challenge_id, "position") DEFERRABLE INITIALLY DEFERRED;


--
-- Name: challenge_steps challenge_steps_tenant_uniq; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.challenge_steps
    ADD CONSTRAINT challenge_steps_tenant_uniq UNIQUE (id, company_id);


--
-- Name: challenges challenges_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.challenges
    ADD CONSTRAINT challenges_pkey PRIMARY KEY (id);


--
-- Name: challenges challenges_tenant_uniq; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.challenges
    ADD CONSTRAINT challenges_tenant_uniq UNIQUE (id, company_id);


--
-- Name: companies companies_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.companies
    ADD CONSTRAINT companies_pkey PRIMARY KEY (id);


--
-- Name: criteria criteria_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.criteria
    ADD CONSTRAINT criteria_pkey PRIMARY KEY (id);


--
-- Name: criteria_sets criteria_sets_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.criteria_sets
    ADD CONSTRAINT criteria_sets_pkey PRIMARY KEY (id);


--
-- Name: criteria_sets criteria_sets_tenant_uniq; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.criteria_sets
    ADD CONSTRAINT criteria_sets_tenant_uniq UNIQUE (id, company_id);


--
-- Name: criteria criteria_tenant_uniq; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.criteria
    ADD CONSTRAINT criteria_tenant_uniq UNIQUE (id, company_id);


--
-- Name: feedback_items feedback_items_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.feedback_items
    ADD CONSTRAINT feedback_items_pkey PRIMARY KEY (id);


--
-- Name: feedback_items feedback_items_tenant_uniq; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.feedback_items
    ADD CONSTRAINT feedback_items_tenant_uniq UNIQUE (id, company_id);


--
-- Name: form_fields form_fields_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.form_fields
    ADD CONSTRAINT form_fields_pkey PRIMARY KEY (id);


--
-- Name: form_fields form_fields_tenant_uniq; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.form_fields
    ADD CONSTRAINT form_fields_tenant_uniq UNIQUE (id, company_id);


--
-- Name: idea_attachments idea_attachments_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.idea_attachments
    ADD CONSTRAINT idea_attachments_pkey PRIMARY KEY (id);


--
-- Name: idea_attachments idea_attachments_tenant_uniq; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.idea_attachments
    ADD CONSTRAINT idea_attachments_tenant_uniq UNIQUE (id, company_id);


--
-- Name: idea_contributors idea_contributors_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.idea_contributors
    ADD CONSTRAINT idea_contributors_pkey PRIMARY KEY (id);


--
-- Name: idea_contributors idea_contributors_tenant_uniq; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.idea_contributors
    ADD CONSTRAINT idea_contributors_tenant_uniq UNIQUE (id, company_id);


--
-- Name: idea_versions idea_versions_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.idea_versions
    ADD CONSTRAINT idea_versions_pkey PRIMARY KEY (id);


--
-- Name: idea_versions idea_versions_tenant_uniq; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.idea_versions
    ADD CONSTRAINT idea_versions_tenant_uniq UNIQUE (id, company_id);


--
-- Name: ideas ideas_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.ideas
    ADD CONSTRAINT ideas_pkey PRIMARY KEY (id);


--
-- Name: ideas ideas_tenant_uniq; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.ideas
    ADD CONSTRAINT ideas_tenant_uniq UNIQUE (id, company_id);


--
-- Name: identities identities_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.identities
    ADD CONSTRAINT identities_pkey PRIMARY KEY (id);


--
-- Name: memberships memberships_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.memberships
    ADD CONSTRAINT memberships_pkey PRIMARY KEY (id);


--
-- Name: memberships memberships_tenant_uniq; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.memberships
    ADD CONSTRAINT memberships_tenant_uniq UNIQUE (id, company_id);


--
-- Name: notifications notifications_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.notifications
    ADD CONSTRAINT notifications_pkey PRIMARY KEY (id);


--
-- Name: notifications notifications_tenant_uniq; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.notifications
    ADD CONSTRAINT notifications_tenant_uniq UNIQUE (id, company_id);


--
-- Name: reports reports_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.reports
    ADD CONSTRAINT reports_pkey PRIMARY KEY (id);


--
-- Name: reports reports_tenant_uniq; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.reports
    ADD CONSTRAINT reports_tenant_uniq UNIQUE (id, company_id);


--
-- Name: schema_migrations schema_migrations_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.schema_migrations
    ADD CONSTRAINT schema_migrations_pkey PRIMARY KEY (version);


--
-- Name: selection_decisions selection_decisions_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.selection_decisions
    ADD CONSTRAINT selection_decisions_pkey PRIMARY KEY (id);


--
-- Name: selection_decisions selection_decisions_tenant_uniq; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.selection_decisions
    ADD CONSTRAINT selection_decisions_tenant_uniq UNIQUE (id, company_id);


--
-- Name: selection_verdicts selection_verdicts_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.selection_verdicts
    ADD CONSTRAINT selection_verdicts_pkey PRIMARY KEY (id);


--
-- Name: selection_verdicts selection_verdicts_tenant_uniq; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.selection_verdicts
    ADD CONSTRAINT selection_verdicts_tenant_uniq UNIQUE (id, company_id);


--
-- Name: sessions sessions_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.sessions
    ADD CONSTRAINT sessions_pkey PRIMARY KEY (id);


--
-- Name: step_assignments step_assignments_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.step_assignments
    ADD CONSTRAINT step_assignments_pkey PRIMARY KEY (id);


--
-- Name: step_assignments step_assignments_tenant_uniq; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.step_assignments
    ADD CONSTRAINT step_assignments_tenant_uniq UNIQUE (id, company_id);


--
-- Name: step_entries step_entries_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.step_entries
    ADD CONSTRAINT step_entries_pkey PRIMARY KEY (id);


--
-- Name: step_entries step_entries_tenant_uniq; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.step_entries
    ADD CONSTRAINT step_entries_tenant_uniq UNIQUE (id, company_id);


--
-- Name: users users_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.users
    ADD CONSTRAINT users_pkey PRIMARY KEY (id);


--
-- Name: idx_on_challenge_step_id_idea_id_decided_at_10400b17a9; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_on_challenge_step_id_idea_id_decided_at_10400b17a9 ON public.selection_decisions USING btree (challenge_step_id, idea_id, decided_at);


--
-- Name: index_active_storage_attachments_on_blob_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_active_storage_attachments_on_blob_id ON public.active_storage_attachments USING btree (blob_id);


--
-- Name: index_active_storage_attachments_uniqueness; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_active_storage_attachments_uniqueness ON public.active_storage_attachments USING btree (record_type, record_id, name, blob_id);


--
-- Name: index_active_storage_blobs_on_key; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_active_storage_blobs_on_key ON public.active_storage_blobs USING btree (key);


--
-- Name: index_active_storage_variant_records_uniqueness; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_active_storage_variant_records_uniqueness ON public.active_storage_variant_records USING btree (blob_id, variation_digest);


--
-- Name: index_ai_runs_on_challenge_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_ai_runs_on_challenge_id ON public.ai_runs USING btree (challenge_id);


--
-- Name: index_ai_runs_on_challenge_step_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_ai_runs_on_challenge_step_id ON public.ai_runs USING btree (challenge_step_id);


--
-- Name: index_ai_runs_on_company_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_ai_runs_on_company_id ON public.ai_runs USING btree (company_id);


--
-- Name: index_ai_runs_on_company_id_and_created_at; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_ai_runs_on_company_id_and_created_at ON public.ai_runs USING btree (company_id, created_at);


--
-- Name: index_ai_runs_on_company_id_and_idempotency_key; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_ai_runs_on_company_id_and_idempotency_key ON public.ai_runs USING btree (company_id, idempotency_key) WHERE (idempotency_key IS NOT NULL);


--
-- Name: index_ai_runs_on_idea_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_ai_runs_on_idea_id ON public.ai_runs USING btree (idea_id);


--
-- Name: index_ai_runs_on_requested_by_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_ai_runs_on_requested_by_id ON public.ai_runs USING btree (requested_by_id);


--
-- Name: index_ai_suggestions_on_ai_run_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_ai_suggestions_on_ai_run_id ON public.ai_suggestions USING btree (ai_run_id);


--
-- Name: index_ai_suggestions_on_company_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_ai_suggestions_on_company_id ON public.ai_suggestions USING btree (company_id);


--
-- Name: index_ai_suggestions_on_reviewed_by_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_ai_suggestions_on_reviewed_by_id ON public.ai_suggestions USING btree (reviewed_by_id);


--
-- Name: index_assessment_scores_on_assessment_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_assessment_scores_on_assessment_id ON public.assessment_scores USING btree (assessment_id);


--
-- Name: index_assessment_scores_on_assessment_id_and_criterion_key; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_assessment_scores_on_assessment_id_and_criterion_key ON public.assessment_scores USING btree (assessment_id, criterion_key);


--
-- Name: index_assessment_scores_on_company_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_assessment_scores_on_company_id ON public.assessment_scores USING btree (company_id);


--
-- Name: index_assessment_scores_on_criterion_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_assessment_scores_on_criterion_id ON public.assessment_scores USING btree (criterion_id);


--
-- Name: index_assessments_on_challenge_step_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_assessments_on_challenge_step_id ON public.assessments USING btree (challenge_step_id);


--
-- Name: index_assessments_on_company_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_assessments_on_company_id ON public.assessments USING btree (company_id);


--
-- Name: index_assessments_on_evaluator_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_assessments_on_evaluator_id ON public.assessments USING btree (evaluator_id);


--
-- Name: index_assessments_on_idea_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_assessments_on_idea_id ON public.assessments USING btree (idea_id);


--
-- Name: index_assessments_unique_ai; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_assessments_unique_ai ON public.assessments USING btree (challenge_step_id, idea_id, ai_run_id) WHERE ((superseded_at IS NULL) AND (evaluator_id IS NULL));


--
-- Name: index_assessments_unique_human; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_assessments_unique_human ON public.assessments USING btree (challenge_step_id, idea_id, evaluator_id) WHERE ((superseded_at IS NULL) AND (evaluator_id IS NOT NULL));


--
-- Name: index_challenge_gestores_on_challenge_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_challenge_gestores_on_challenge_id ON public.challenge_gestores USING btree (challenge_id);


--
-- Name: index_challenge_gestores_on_challenge_id_and_user_id; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_challenge_gestores_on_challenge_id_and_user_id ON public.challenge_gestores USING btree (challenge_id, user_id);


--
-- Name: index_challenge_gestores_on_company_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_challenge_gestores_on_company_id ON public.challenge_gestores USING btree (company_id);


--
-- Name: index_challenge_gestores_on_user_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_challenge_gestores_on_user_id ON public.challenge_gestores USING btree (user_id);


--
-- Name: index_challenge_steps_on_challenge_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_challenge_steps_on_challenge_id ON public.challenge_steps USING btree (challenge_id);


--
-- Name: index_challenge_steps_on_challenge_id_and_slug; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_challenge_steps_on_challenge_id_and_slug ON public.challenge_steps USING btree (challenge_id, slug);


--
-- Name: index_challenge_steps_on_challenge_id_and_status; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_challenge_steps_on_challenge_id_and_status ON public.challenge_steps USING btree (challenge_id, status);


--
-- Name: index_challenge_steps_on_company_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_challenge_steps_on_company_id ON public.challenge_steps USING btree (company_id);


--
-- Name: index_challenge_steps_on_criteria_set_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_challenge_steps_on_criteria_set_id ON public.challenge_steps USING btree (criteria_set_id);


--
-- Name: index_challenge_steps_single_ideation; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_challenge_steps_single_ideation ON public.challenge_steps USING btree (challenge_id) WHERE ((kind)::text = 'ideation'::text);


--
-- Name: index_challenges_on_company_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_challenges_on_company_id ON public.challenges USING btree (company_id);


--
-- Name: index_challenges_on_company_id_and_slug; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_challenges_on_company_id_and_slug ON public.challenges USING btree (company_id, slug);


--
-- Name: index_companies_on_slug; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_companies_on_slug ON public.companies USING btree (slug);


--
-- Name: index_criteria_on_company_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_criteria_on_company_id ON public.criteria USING btree (company_id);


--
-- Name: index_criteria_on_criteria_set_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_criteria_on_criteria_set_id ON public.criteria USING btree (criteria_set_id);


--
-- Name: index_criteria_on_criteria_set_id_and_key; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_criteria_on_criteria_set_id_and_key ON public.criteria USING btree (criteria_set_id, key);


--
-- Name: index_criteria_sets_on_company_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_criteria_sets_on_company_id ON public.criteria_sets USING btree (company_id);


--
-- Name: index_criteria_sets_on_family_id_and_version; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_criteria_sets_on_family_id_and_version ON public.criteria_sets USING btree (family_id, version);


--
-- Name: index_criteria_sets_on_superseded_at; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_criteria_sets_on_superseded_at ON public.criteria_sets USING btree (superseded_at);


--
-- Name: index_feedback_items_on_author_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_feedback_items_on_author_id ON public.feedback_items USING btree (author_id);


--
-- Name: index_feedback_items_on_challenge_step_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_feedback_items_on_challenge_step_id ON public.feedback_items USING btree (challenge_step_id);


--
-- Name: index_feedback_items_on_company_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_feedback_items_on_company_id ON public.feedback_items USING btree (company_id);


--
-- Name: index_feedback_items_on_idea_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_feedback_items_on_idea_id ON public.feedback_items USING btree (idea_id);


--
-- Name: index_feedback_items_on_idea_id_and_addressed; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_feedback_items_on_idea_id_and_addressed ON public.feedback_items USING btree (idea_id, addressed);


--
-- Name: index_feedback_items_on_resolved_by_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_feedback_items_on_resolved_by_id ON public.feedback_items USING btree (resolved_by_id);


--
-- Name: index_form_fields_on_challenge_step_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_form_fields_on_challenge_step_id ON public.form_fields USING btree (challenge_step_id);


--
-- Name: index_form_fields_on_challenge_step_id_and_key; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_form_fields_on_challenge_step_id_and_key ON public.form_fields USING btree (challenge_step_id, key);


--
-- Name: index_form_fields_on_company_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_form_fields_on_company_id ON public.form_fields USING btree (company_id);


--
-- Name: index_idea_attachments_on_company_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_idea_attachments_on_company_id ON public.idea_attachments USING btree (company_id);


--
-- Name: index_idea_attachments_on_idea_version_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_idea_attachments_on_idea_version_id ON public.idea_attachments USING btree (idea_version_id);


--
-- Name: index_idea_contributors_on_company_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_idea_contributors_on_company_id ON public.idea_contributors USING btree (company_id);


--
-- Name: index_idea_contributors_on_idea_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_idea_contributors_on_idea_id ON public.idea_contributors USING btree (idea_id);


--
-- Name: index_idea_contributors_on_idea_id_and_user_id; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_idea_contributors_on_idea_id_and_user_id ON public.idea_contributors USING btree (idea_id, user_id);


--
-- Name: index_idea_contributors_on_user_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_idea_contributors_on_user_id ON public.idea_contributors USING btree (user_id);


--
-- Name: index_idea_versions_on_company_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_idea_versions_on_company_id ON public.idea_versions USING btree (company_id);


--
-- Name: index_idea_versions_on_created_by_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_idea_versions_on_created_by_id ON public.idea_versions USING btree (created_by_id);


--
-- Name: index_idea_versions_on_idea_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_idea_versions_on_idea_id ON public.idea_versions USING btree (idea_id);


--
-- Name: index_idea_versions_on_idea_id_and_number; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_idea_versions_on_idea_id_and_number ON public.idea_versions USING btree (idea_id, number);


--
-- Name: index_ideas_on_author_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_ideas_on_author_id ON public.ideas USING btree (author_id);


--
-- Name: index_ideas_on_challenge_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_ideas_on_challenge_id ON public.ideas USING btree (challenge_id);


--
-- Name: index_ideas_on_challenge_id_and_status; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_ideas_on_challenge_id_and_status ON public.ideas USING btree (challenge_id, status);


--
-- Name: index_ideas_on_company_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_ideas_on_company_id ON public.ideas USING btree (company_id);


--
-- Name: index_identities_on_provider_and_uid; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_identities_on_provider_and_uid ON public.identities USING btree (provider, uid);


--
-- Name: index_identities_on_user_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_identities_on_user_id ON public.identities USING btree (user_id);


--
-- Name: index_memberships_on_company_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_memberships_on_company_id ON public.memberships USING btree (company_id);


--
-- Name: index_memberships_on_company_id_and_user_id; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_memberships_on_company_id_and_user_id ON public.memberships USING btree (company_id, user_id);


--
-- Name: index_memberships_on_user_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_memberships_on_user_id ON public.memberships USING btree (user_id);


--
-- Name: index_notifications_on_challenge_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_notifications_on_challenge_id ON public.notifications USING btree (challenge_id);


--
-- Name: index_notifications_on_challenge_step_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_notifications_on_challenge_step_id ON public.notifications USING btree (challenge_step_id);


--
-- Name: index_notifications_on_company_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_notifications_on_company_id ON public.notifications USING btree (company_id);


--
-- Name: index_notifications_on_idea_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_notifications_on_idea_id ON public.notifications USING btree (idea_id);


--
-- Name: index_notifications_on_user_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_notifications_on_user_id ON public.notifications USING btree (user_id);


--
-- Name: index_notifications_on_user_id_and_read_at_and_created_at; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_notifications_on_user_id_and_read_at_and_created_at ON public.notifications USING btree (user_id, read_at, created_at DESC);


--
-- Name: index_reports_on_challenge_step_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_reports_on_challenge_step_id ON public.reports USING btree (challenge_step_id);


--
-- Name: index_reports_on_company_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_reports_on_company_id ON public.reports USING btree (company_id);


--
-- Name: index_reports_on_requested_by_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_reports_on_requested_by_id ON public.reports USING btree (requested_by_id);


--
-- Name: index_selection_decisions_on_challenge_step_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_selection_decisions_on_challenge_step_id ON public.selection_decisions USING btree (challenge_step_id);


--
-- Name: index_selection_decisions_on_company_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_selection_decisions_on_company_id ON public.selection_decisions USING btree (company_id);


--
-- Name: index_selection_decisions_on_decided_by_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_selection_decisions_on_decided_by_id ON public.selection_decisions USING btree (decided_by_id);


--
-- Name: index_selection_decisions_on_idea_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_selection_decisions_on_idea_id ON public.selection_decisions USING btree (idea_id);


--
-- Name: index_selection_verdicts_on_challenge_step_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_selection_verdicts_on_challenge_step_id ON public.selection_verdicts USING btree (challenge_step_id);


--
-- Name: index_selection_verdicts_on_company_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_selection_verdicts_on_company_id ON public.selection_verdicts USING btree (company_id);


--
-- Name: index_selection_verdicts_on_decided_by_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_selection_verdicts_on_decided_by_id ON public.selection_verdicts USING btree (decided_by_id);


--
-- Name: index_selection_verdicts_on_idea_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_selection_verdicts_on_idea_id ON public.selection_verdicts USING btree (idea_id);


--
-- Name: index_selection_verdicts_unique; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_selection_verdicts_unique ON public.selection_verdicts USING btree (challenge_step_id, idea_id, criterion_key);


--
-- Name: index_sessions_on_company_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_sessions_on_company_id ON public.sessions USING btree (company_id);


--
-- Name: index_sessions_on_token; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_sessions_on_token ON public.sessions USING btree (token);


--
-- Name: index_sessions_on_user_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_sessions_on_user_id ON public.sessions USING btree (user_id);


--
-- Name: index_step_assignments_on_challenge_step_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_step_assignments_on_challenge_step_id ON public.step_assignments USING btree (challenge_step_id);


--
-- Name: index_step_assignments_on_challenge_step_id_and_user_id; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_step_assignments_on_challenge_step_id_and_user_id ON public.step_assignments USING btree (challenge_step_id, user_id);


--
-- Name: index_step_assignments_on_company_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_step_assignments_on_company_id ON public.step_assignments USING btree (company_id);


--
-- Name: index_step_assignments_on_user_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_step_assignments_on_user_id ON public.step_assignments USING btree (user_id);


--
-- Name: index_step_entries_on_challenge_step_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_step_entries_on_challenge_step_id ON public.step_entries USING btree (challenge_step_id);


--
-- Name: index_step_entries_on_challenge_step_id_and_idea_id; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_step_entries_on_challenge_step_id_and_idea_id ON public.step_entries USING btree (challenge_step_id, idea_id);


--
-- Name: index_step_entries_on_company_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_step_entries_on_company_id ON public.step_entries USING btree (company_id);


--
-- Name: index_step_entries_on_idea_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_step_entries_on_idea_id ON public.step_entries USING btree (idea_id);


--
-- Name: index_users_on_lower_email; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_users_on_lower_email ON public.users USING btree (lower((email)::text));


--
-- Name: ai_runs ai_runs_challenge_id_same_company; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.ai_runs
    ADD CONSTRAINT ai_runs_challenge_id_same_company FOREIGN KEY (challenge_id, company_id) REFERENCES public.challenges(id, company_id) ON DELETE CASCADE;


--
-- Name: ai_runs ai_runs_challenge_step_id_same_company; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.ai_runs
    ADD CONSTRAINT ai_runs_challenge_step_id_same_company FOREIGN KEY (challenge_step_id, company_id) REFERENCES public.challenge_steps(id, company_id) ON DELETE CASCADE;


--
-- Name: ai_runs ai_runs_idea_id_same_company; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.ai_runs
    ADD CONSTRAINT ai_runs_idea_id_same_company FOREIGN KEY (idea_id, company_id) REFERENCES public.ideas(id, company_id) ON DELETE CASCADE;


--
-- Name: ai_suggestions ai_suggestions_ai_run_id_same_company; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.ai_suggestions
    ADD CONSTRAINT ai_suggestions_ai_run_id_same_company FOREIGN KEY (ai_run_id, company_id) REFERENCES public.ai_runs(id, company_id) ON DELETE CASCADE;


--
-- Name: ai_suggestions ai_suggestions_challenge_id_same_company; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.ai_suggestions
    ADD CONSTRAINT ai_suggestions_challenge_id_same_company FOREIGN KEY (challenge_id, company_id) REFERENCES public.challenges(id, company_id) ON DELETE CASCADE;


--
-- Name: ai_suggestions ai_suggestions_challenge_step_id_same_company; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.ai_suggestions
    ADD CONSTRAINT ai_suggestions_challenge_step_id_same_company FOREIGN KEY (challenge_step_id, company_id) REFERENCES public.challenge_steps(id, company_id) ON DELETE CASCADE;


--
-- Name: ai_suggestions ai_suggestions_idea_id_same_company; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.ai_suggestions
    ADD CONSTRAINT ai_suggestions_idea_id_same_company FOREIGN KEY (idea_id, company_id) REFERENCES public.ideas(id, company_id) ON DELETE CASCADE;


--
-- Name: assessment_scores assessment_scores_assessment_id_same_company; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.assessment_scores
    ADD CONSTRAINT assessment_scores_assessment_id_same_company FOREIGN KEY (assessment_id, company_id) REFERENCES public.assessments(id, company_id) ON DELETE CASCADE;


--
-- Name: assessment_scores assessment_scores_criterion_id_same_company; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.assessment_scores
    ADD CONSTRAINT assessment_scores_criterion_id_same_company FOREIGN KEY (criterion_id, company_id) REFERENCES public.criteria(id, company_id) ON DELETE SET NULL (criterion_id);


--
-- Name: assessments assessments_ai_run_id_same_company; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.assessments
    ADD CONSTRAINT assessments_ai_run_id_same_company FOREIGN KEY (ai_run_id, company_id) REFERENCES public.ai_runs(id, company_id) ON DELETE SET NULL (ai_run_id);


--
-- Name: assessments assessments_challenge_step_id_same_company; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.assessments
    ADD CONSTRAINT assessments_challenge_step_id_same_company FOREIGN KEY (challenge_step_id, company_id) REFERENCES public.challenge_steps(id, company_id) ON DELETE CASCADE;


--
-- Name: assessments assessments_idea_id_same_company; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.assessments
    ADD CONSTRAINT assessments_idea_id_same_company FOREIGN KEY (idea_id, company_id) REFERENCES public.ideas(id, company_id) ON DELETE CASCADE;


--
-- Name: assessments assessments_idea_version_id_same_company; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.assessments
    ADD CONSTRAINT assessments_idea_version_id_same_company FOREIGN KEY (idea_version_id, company_id) REFERENCES public.idea_versions(id, company_id) ON DELETE CASCADE;


--
-- Name: challenge_gestores challenge_gestores_challenge_id_same_company; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.challenge_gestores
    ADD CONSTRAINT challenge_gestores_challenge_id_same_company FOREIGN KEY (challenge_id, company_id) REFERENCES public.challenges(id, company_id) ON DELETE CASCADE;


--
-- Name: challenge_steps challenge_steps_challenge_id_same_company; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.challenge_steps
    ADD CONSTRAINT challenge_steps_challenge_id_same_company FOREIGN KEY (challenge_id, company_id) REFERENCES public.challenges(id, company_id) ON DELETE CASCADE;


--
-- Name: challenge_steps challenge_steps_criteria_set_id_same_company; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.challenge_steps
    ADD CONSTRAINT challenge_steps_criteria_set_id_same_company FOREIGN KEY (criteria_set_id, company_id) REFERENCES public.criteria_sets(id, company_id) ON DELETE SET NULL (criteria_set_id);


--
-- Name: challenge_steps challenge_steps_source_step_id_same_company; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.challenge_steps
    ADD CONSTRAINT challenge_steps_source_step_id_same_company FOREIGN KEY (source_step_id, company_id) REFERENCES public.challenge_steps(id, company_id) ON DELETE SET NULL (source_step_id);


--
-- Name: criteria criteria_criteria_set_id_same_company; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.criteria
    ADD CONSTRAINT criteria_criteria_set_id_same_company FOREIGN KEY (criteria_set_id, company_id) REFERENCES public.criteria_sets(id, company_id) ON DELETE CASCADE;


--
-- Name: criteria_sets criteria_sets_owner_step_id_same_company; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.criteria_sets
    ADD CONSTRAINT criteria_sets_owner_step_id_same_company FOREIGN KEY (owner_step_id, company_id) REFERENCES public.challenge_steps(id, company_id) ON DELETE CASCADE;


--
-- Name: feedback_items feedback_items_addressed_by_version_id_same_company; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.feedback_items
    ADD CONSTRAINT feedback_items_addressed_by_version_id_same_company FOREIGN KEY (addressed_by_version_id, company_id) REFERENCES public.idea_versions(id, company_id) ON DELETE SET NULL (addressed_by_version_id);


--
-- Name: feedback_items feedback_items_ai_run_id_same_company; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.feedback_items
    ADD CONSTRAINT feedback_items_ai_run_id_same_company FOREIGN KEY (ai_run_id, company_id) REFERENCES public.ai_runs(id, company_id) ON DELETE SET NULL (ai_run_id);


--
-- Name: feedback_items feedback_items_challenge_step_id_same_company; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.feedback_items
    ADD CONSTRAINT feedback_items_challenge_step_id_same_company FOREIGN KEY (challenge_step_id, company_id) REFERENCES public.challenge_steps(id, company_id) ON DELETE CASCADE;


--
-- Name: feedback_items feedback_items_idea_id_same_company; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.feedback_items
    ADD CONSTRAINT feedback_items_idea_id_same_company FOREIGN KEY (idea_id, company_id) REFERENCES public.ideas(id, company_id) ON DELETE CASCADE;


--
-- Name: feedback_items feedback_items_idea_version_id_same_company; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.feedback_items
    ADD CONSTRAINT feedback_items_idea_version_id_same_company FOREIGN KEY (idea_version_id, company_id) REFERENCES public.idea_versions(id, company_id) ON DELETE CASCADE;


--
-- Name: assessment_scores fk_rails_0534760f81; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.assessment_scores
    ADD CONSTRAINT fk_rails_0534760f81 FOREIGN KEY (company_id) REFERENCES public.companies(id);


--
-- Name: challenge_steps fk_rails_0b96987740; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.challenge_steps
    ADD CONSTRAINT fk_rails_0b96987740 FOREIGN KEY (company_id) REFERENCES public.companies(id);


--
-- Name: ai_suggestions fk_rails_1156bc766f; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.ai_suggestions
    ADD CONSTRAINT fk_rails_1156bc766f FOREIGN KEY (reviewed_by_id) REFERENCES public.users(id);


--
-- Name: challenges fk_rails_1353858338; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.challenges
    ADD CONSTRAINT fk_rails_1353858338 FOREIGN KEY (company_id) REFERENCES public.companies(id);


--
-- Name: selection_verdicts fk_rails_23a73449bd; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.selection_verdicts
    ADD CONSTRAINT fk_rails_23a73449bd FOREIGN KEY (company_id) REFERENCES public.companies(id);


--
-- Name: idea_contributors fk_rails_290fa5feb0; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.idea_contributors
    ADD CONSTRAINT fk_rails_290fa5feb0 FOREIGN KEY (user_id) REFERENCES public.users(id);


--
-- Name: reports fk_rails_38dc9ec35b; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.reports
    ADD CONSTRAINT fk_rails_38dc9ec35b FOREIGN KEY (company_id) REFERENCES public.companies(id);


--
-- Name: step_entries fk_rails_52275a5a1d; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.step_entries
    ADD CONSTRAINT fk_rails_52275a5a1d FOREIGN KEY (company_id) REFERENCES public.companies(id);


--
-- Name: identities fk_rails_5373344100; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.identities
    ADD CONSTRAINT fk_rails_5373344100 FOREIGN KEY (user_id) REFERENCES public.users(id);


--
-- Name: feedback_items fk_rails_5ba7f8a820; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.feedback_items
    ADD CONSTRAINT fk_rails_5ba7f8a820 FOREIGN KEY (company_id) REFERENCES public.companies(id);


--
-- Name: step_assignments fk_rails_5dcba4f767; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.step_assignments
    ADD CONSTRAINT fk_rails_5dcba4f767 FOREIGN KEY (company_id) REFERENCES public.companies(id);


--
-- Name: criteria fk_rails_6f6468384e; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.criteria
    ADD CONSTRAINT fk_rails_6f6468384e FOREIGN KEY (company_id) REFERENCES public.companies(id);


--
-- Name: challenge_gestores fk_rails_7153b732e3; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.challenge_gestores
    ADD CONSTRAINT fk_rails_7153b732e3 FOREIGN KEY (user_id) REFERENCES public.users(id);


--
-- Name: sessions fk_rails_758836b4f0; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.sessions
    ADD CONSTRAINT fk_rails_758836b4f0 FOREIGN KEY (user_id) REFERENCES public.users(id);


--
-- Name: sessions fk_rails_765e28851b; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.sessions
    ADD CONSTRAINT fk_rails_765e28851b FOREIGN KEY (company_id) REFERENCES public.companies(id);


--
-- Name: ai_runs fk_rails_80e4cc04b9; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.ai_runs
    ADD CONSTRAINT fk_rails_80e4cc04b9 FOREIGN KEY (company_id) REFERENCES public.companies(id);


--
-- Name: idea_attachments fk_rails_8de34be649; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.idea_attachments
    ADD CONSTRAINT fk_rails_8de34be649 FOREIGN KEY (company_id) REFERENCES public.companies(id);


--
-- Name: challenge_gestores fk_rails_96326bc47c; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.challenge_gestores
    ADD CONSTRAINT fk_rails_96326bc47c FOREIGN KEY (company_id) REFERENCES public.companies(id);


--
-- Name: ideas fk_rails_97ddd29c4a; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.ideas
    ADD CONSTRAINT fk_rails_97ddd29c4a FOREIGN KEY (company_id) REFERENCES public.companies(id);


--
-- Name: memberships fk_rails_99326fb65d; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.memberships
    ADD CONSTRAINT fk_rails_99326fb65d FOREIGN KEY (user_id) REFERENCES public.users(id);


--
-- Name: active_storage_variant_records fk_rails_993965df05; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.active_storage_variant_records
    ADD CONSTRAINT fk_rails_993965df05 FOREIGN KEY (blob_id) REFERENCES public.active_storage_blobs(id);


--
-- Name: reports fk_rails_9e9c679e9e; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.reports
    ADD CONSTRAINT fk_rails_9e9c679e9e FOREIGN KEY (requested_by_id) REFERENCES public.users(id);


--
-- Name: form_fields fk_rails_a0939b5963; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.form_fields
    ADD CONSTRAINT fk_rails_a0939b5963 FOREIGN KEY (company_id) REFERENCES public.companies(id);


--
-- Name: ideas fk_rails_a7a91f1df3; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.ideas
    ADD CONSTRAINT fk_rails_a7a91f1df3 FOREIGN KEY (author_id) REFERENCES public.users(id);


--
-- Name: ai_runs fk_rails_af497563ca; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.ai_runs
    ADD CONSTRAINT fk_rails_af497563ca FOREIGN KEY (requested_by_id) REFERENCES public.users(id);


--
-- Name: notifications fk_rails_b080fb4855; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.notifications
    ADD CONSTRAINT fk_rails_b080fb4855 FOREIGN KEY (user_id) REFERENCES public.users(id);


--
-- Name: notifications fk_rails_b7b9be1aed; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.notifications
    ADD CONSTRAINT fk_rails_b7b9be1aed FOREIGN KEY (company_id) REFERENCES public.companies(id);


--
-- Name: selection_verdicts fk_rails_b92213ac1d; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.selection_verdicts
    ADD CONSTRAINT fk_rails_b92213ac1d FOREIGN KEY (decided_by_id) REFERENCES public.users(id);


--
-- Name: idea_versions fk_rails_bbbe1a4148; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.idea_versions
    ADD CONSTRAINT fk_rails_bbbe1a4148 FOREIGN KEY (company_id) REFERENCES public.companies(id);


--
-- Name: feedback_items fk_rails_bf283495fd; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.feedback_items
    ADD CONSTRAINT fk_rails_bf283495fd FOREIGN KEY (resolved_by_id) REFERENCES public.users(id);


--
-- Name: active_storage_attachments fk_rails_c3b3935057; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.active_storage_attachments
    ADD CONSTRAINT fk_rails_c3b3935057 FOREIGN KEY (blob_id) REFERENCES public.active_storage_blobs(id);


--
-- Name: idea_versions fk_rails_c93aae3895; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.idea_versions
    ADD CONSTRAINT fk_rails_c93aae3895 FOREIGN KEY (created_by_id) REFERENCES public.users(id);


--
-- Name: criteria_sets fk_rails_c95ad35424; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.criteria_sets
    ADD CONSTRAINT fk_rails_c95ad35424 FOREIGN KEY (company_id) REFERENCES public.companies(id);


--
-- Name: idea_contributors fk_rails_ce7b3ef58e; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.idea_contributors
    ADD CONSTRAINT fk_rails_ce7b3ef58e FOREIGN KEY (company_id) REFERENCES public.companies(id);


--
-- Name: selection_decisions fk_rails_d10e1bb0f8; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.selection_decisions
    ADD CONSTRAINT fk_rails_d10e1bb0f8 FOREIGN KEY (company_id) REFERENCES public.companies(id);


--
-- Name: feedback_items fk_rails_d4810deefc; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.feedback_items
    ADD CONSTRAINT fk_rails_d4810deefc FOREIGN KEY (author_id) REFERENCES public.users(id);


--
-- Name: assessments fk_rails_dfe95f2fb1; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.assessments
    ADD CONSTRAINT fk_rails_dfe95f2fb1 FOREIGN KEY (evaluator_id) REFERENCES public.users(id);


--
-- Name: selection_decisions fk_rails_e83adf3511; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.selection_decisions
    ADD CONSTRAINT fk_rails_e83adf3511 FOREIGN KEY (decided_by_id) REFERENCES public.users(id);


--
-- Name: step_assignments fk_rails_f033ae6ec4; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.step_assignments
    ADD CONSTRAINT fk_rails_f033ae6ec4 FOREIGN KEY (user_id) REFERENCES public.users(id);


--
-- Name: memberships fk_rails_f2d0ed6100; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.memberships
    ADD CONSTRAINT fk_rails_f2d0ed6100 FOREIGN KEY (company_id) REFERENCES public.companies(id);


--
-- Name: assessments fk_rails_f5357f7fc3; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.assessments
    ADD CONSTRAINT fk_rails_f5357f7fc3 FOREIGN KEY (company_id) REFERENCES public.companies(id);


--
-- Name: ai_suggestions fk_rails_ff37673760; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.ai_suggestions
    ADD CONSTRAINT fk_rails_ff37673760 FOREIGN KEY (company_id) REFERENCES public.companies(id);


--
-- Name: form_fields form_fields_challenge_step_id_same_company; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.form_fields
    ADD CONSTRAINT form_fields_challenge_step_id_same_company FOREIGN KEY (challenge_step_id, company_id) REFERENCES public.challenge_steps(id, company_id) ON DELETE CASCADE;


--
-- Name: idea_attachments idea_attachments_idea_version_id_same_company; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.idea_attachments
    ADD CONSTRAINT idea_attachments_idea_version_id_same_company FOREIGN KEY (idea_version_id, company_id) REFERENCES public.idea_versions(id, company_id) ON DELETE CASCADE;


--
-- Name: idea_contributors idea_contributors_idea_id_same_company; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.idea_contributors
    ADD CONSTRAINT idea_contributors_idea_id_same_company FOREIGN KEY (idea_id, company_id) REFERENCES public.ideas(id, company_id) ON DELETE CASCADE;


--
-- Name: idea_versions idea_versions_idea_id_same_company; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.idea_versions
    ADD CONSTRAINT idea_versions_idea_id_same_company FOREIGN KEY (idea_id, company_id) REFERENCES public.ideas(id, company_id) ON DELETE CASCADE;


--
-- Name: idea_versions idea_versions_source_step_id_same_company; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.idea_versions
    ADD CONSTRAINT idea_versions_source_step_id_same_company FOREIGN KEY (source_step_id, company_id) REFERENCES public.challenge_steps(id, company_id) ON DELETE SET NULL (source_step_id);


--
-- Name: ideas ideas_challenge_id_same_company; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.ideas
    ADD CONSTRAINT ideas_challenge_id_same_company FOREIGN KEY (challenge_id, company_id) REFERENCES public.challenges(id, company_id) ON DELETE CASCADE;


--
-- Name: ideas ideas_current_version_id_same_company; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.ideas
    ADD CONSTRAINT ideas_current_version_id_same_company FOREIGN KEY (current_version_id, company_id) REFERENCES public.idea_versions(id, company_id) ON DELETE SET NULL (current_version_id);


--
-- Name: notifications notifications_challenge_id_same_company; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.notifications
    ADD CONSTRAINT notifications_challenge_id_same_company FOREIGN KEY (challenge_id, company_id) REFERENCES public.challenges(id, company_id) ON DELETE CASCADE;


--
-- Name: notifications notifications_challenge_step_id_same_company; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.notifications
    ADD CONSTRAINT notifications_challenge_step_id_same_company FOREIGN KEY (challenge_step_id, company_id) REFERENCES public.challenge_steps(id, company_id) ON DELETE CASCADE;


--
-- Name: notifications notifications_idea_id_same_company; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.notifications
    ADD CONSTRAINT notifications_idea_id_same_company FOREIGN KEY (idea_id, company_id) REFERENCES public.ideas(id, company_id) ON DELETE CASCADE;


--
-- Name: reports reports_ai_run_id_same_company; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.reports
    ADD CONSTRAINT reports_ai_run_id_same_company FOREIGN KEY (ai_run_id, company_id) REFERENCES public.ai_runs(id, company_id) ON DELETE SET NULL (ai_run_id);


--
-- Name: reports reports_challenge_step_id_same_company; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.reports
    ADD CONSTRAINT reports_challenge_step_id_same_company FOREIGN KEY (challenge_step_id, company_id) REFERENCES public.challenge_steps(id, company_id) ON DELETE CASCADE;


--
-- Name: selection_decisions selection_decisions_challenge_step_id_same_company; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.selection_decisions
    ADD CONSTRAINT selection_decisions_challenge_step_id_same_company FOREIGN KEY (challenge_step_id, company_id) REFERENCES public.challenge_steps(id, company_id) ON DELETE CASCADE;


--
-- Name: selection_decisions selection_decisions_idea_id_same_company; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.selection_decisions
    ADD CONSTRAINT selection_decisions_idea_id_same_company FOREIGN KEY (idea_id, company_id) REFERENCES public.ideas(id, company_id) ON DELETE CASCADE;


--
-- Name: selection_decisions selection_decisions_idea_version_id_same_company; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.selection_decisions
    ADD CONSTRAINT selection_decisions_idea_version_id_same_company FOREIGN KEY (idea_version_id, company_id) REFERENCES public.idea_versions(id, company_id) ON DELETE CASCADE;


--
-- Name: selection_verdicts selection_verdicts_ai_run_id_same_company; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.selection_verdicts
    ADD CONSTRAINT selection_verdicts_ai_run_id_same_company FOREIGN KEY (ai_run_id, company_id) REFERENCES public.ai_runs(id, company_id) ON DELETE SET NULL;


--
-- Name: selection_verdicts selection_verdicts_challenge_step_id_same_company; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.selection_verdicts
    ADD CONSTRAINT selection_verdicts_challenge_step_id_same_company FOREIGN KEY (challenge_step_id, company_id) REFERENCES public.challenge_steps(id, company_id) ON DELETE CASCADE;


--
-- Name: selection_verdicts selection_verdicts_criterion_id_same_company; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.selection_verdicts
    ADD CONSTRAINT selection_verdicts_criterion_id_same_company FOREIGN KEY (criterion_id, company_id) REFERENCES public.criteria(id, company_id) ON DELETE SET NULL;


--
-- Name: selection_verdicts selection_verdicts_idea_id_same_company; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.selection_verdicts
    ADD CONSTRAINT selection_verdicts_idea_id_same_company FOREIGN KEY (idea_id, company_id) REFERENCES public.ideas(id, company_id) ON DELETE CASCADE;


--
-- Name: selection_verdicts selection_verdicts_idea_version_id_same_company; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.selection_verdicts
    ADD CONSTRAINT selection_verdicts_idea_version_id_same_company FOREIGN KEY (idea_version_id, company_id) REFERENCES public.idea_versions(id, company_id) ON DELETE CASCADE;


--
-- Name: step_assignments step_assignments_challenge_step_id_same_company; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.step_assignments
    ADD CONSTRAINT step_assignments_challenge_step_id_same_company FOREIGN KEY (challenge_step_id, company_id) REFERENCES public.challenge_steps(id, company_id) ON DELETE CASCADE;


--
-- Name: step_entries step_entries_challenge_step_id_same_company; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.step_entries
    ADD CONSTRAINT step_entries_challenge_step_id_same_company FOREIGN KEY (challenge_step_id, company_id) REFERENCES public.challenge_steps(id, company_id) ON DELETE CASCADE;


--
-- Name: step_entries step_entries_idea_id_same_company; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.step_entries
    ADD CONSTRAINT step_entries_idea_id_same_company FOREIGN KEY (idea_id, company_id) REFERENCES public.ideas(id, company_id) ON DELETE CASCADE;


--
-- Name: step_entries step_entries_input_version_id_same_company; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.step_entries
    ADD CONSTRAINT step_entries_input_version_id_same_company FOREIGN KEY (input_version_id, company_id) REFERENCES public.idea_versions(id, company_id) ON DELETE SET NULL (input_version_id);


--
-- Name: step_entries step_entries_output_version_id_same_company; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.step_entries
    ADD CONSTRAINT step_entries_output_version_id_same_company FOREIGN KEY (output_version_id, company_id) REFERENCES public.idea_versions(id, company_id) ON DELETE SET NULL (output_version_id);


--
-- PostgreSQL database dump complete
--

\unrestrict cSrLNLaNA3LiyaBJ8ywYyM7U6gEcIjqfBtpjz3qVkrz1cHGeeheNbLMrdPhjyu1

SET search_path TO "$user", public;

INSERT INTO "schema_migrations" (version) VALUES
('20260904140000'),
('20260904100000'),
('20260903200000'),
('20260903190000'),
('20260903170000'),
('20260902180000'),
('20260901150000'),
('20260901140000'),
('20260901130000'),
('20260901120000'),
('20260831223705'),
('20260831210000'),
('20260831200000'),
('20260831190000'),
('20260831180000'),
('20260831170000'),
('20260831160000'),
('20260831150000'),
('20260831140000'),
('20260831130000'),
('20260831120100'),
('20260831120000');

