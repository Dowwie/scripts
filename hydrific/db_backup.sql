--
-- PostgreSQL database dump
--

-- Dumped from database version 15.6 (Ubuntu 15.6-1.pgdg22.04+1)
-- Dumped by pg_dump version 15.6 (Homebrew)

-- Started on 2024-04-30 17:03:51 EDT

SET statement_timeout = 0;
SET lock_timeout = 0;
SET idle_in_transaction_session_timeout = 0;
SET client_encoding = 'UTF8';
SET standard_conforming_strings = on;
SELECT pg_catalog.set_config('search_path', '', false);
SET check_function_bodies = false;
SET xmloption = content;
SET client_min_messages = warning;
SET row_security = off;

--
-- TOC entry 13 (class 2615 OID 2200)
-- Name: public; Type: SCHEMA; Schema: -; Owner: tsdbadmin
--

-- *not* creating schema, since initdb creates it


ALTER SCHEMA public OWNER TO tsdbadmin;

--
-- TOC entry 5 (class 3079 OID 16511)
-- Name: timescaledb; Type: EXTENSION; Schema: -; Owner: -
--

CREATE EXTENSION IF NOT EXISTS timescaledb WITH SCHEMA public;


--
-- TOC entry 7545 (class 0 OID 0)
-- Dependencies: 5
-- Name: EXTENSION timescaledb; Type: COMMENT; Schema: -; Owner:
--

COMMENT ON EXTENSION timescaledb IS 'Enables scalable inserts and complex queries for time-series data (Community Edition)';


--
-- TOC entry 4 (class 3079 OID 26129)
-- Name: timescaledb_osm; Type: EXTENSION; Schema: -; Owner: -
--

CREATE EXTENSION IF NOT EXISTS timescaledb_osm WITH SCHEMA public;


--
-- TOC entry 7546 (class 0 OID 0)
-- Dependencies: 4
-- Name: EXTENSION timescaledb_osm; Type: COMMENT; Schema: -; Owner:
--

COMMENT ON EXTENSION timescaledb_osm IS 'Manages object storage on S3';


--
-- TOC entry 3 (class 3079 OID 17258)
-- Name: timescaledb_toolkit; Type: EXTENSION; Schema: -; Owner: -
--

CREATE EXTENSION IF NOT EXISTS timescaledb_toolkit WITH SCHEMA public;


--
-- TOC entry 7555 (class 0 OID 0)
-- Dependencies: 3
-- Name: EXTENSION timescaledb_toolkit; Type: COMMENT; Schema: -; Owner:
--

COMMENT ON EXTENSION timescaledb_toolkit IS 'Library of analytical hyperfunctions, time-series pipelining, and other SQL utilities';


--
-- TOC entry 2 (class 3079 OID 16480)
-- Name: pg_stat_statements; Type: EXTENSION; Schema: -; Owner: -
--

CREATE EXTENSION IF NOT EXISTS pg_stat_statements WITH SCHEMA public;


--
-- TOC entry 7556 (class 0 OID 0)
-- Dependencies: 2
-- Name: EXTENSION pg_stat_statements; Type: COMMENT; Schema: -; Owner:
--

COMMENT ON EXTENSION pg_stat_statements IS 'track planning and execution statistics of all SQL statements executed';


--
-- TOC entry 1816 (class 1255 OID 53705)
-- Name: create_playground(regclass, boolean); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION public.create_playground(src_hypertable regclass, compressed boolean DEFAULT false) RETURNS text
    LANGUAGE plpgsql
    SET search_path TO 'pg_catalog', 'pg_temp'
    AS $_$
DECLARE
    _table_name NAME;
    _schema_name NAME;
    _src_relation NAME;
    _playground_table_fqn NAME;
    _chunk_name NAME;
    _chunk_check BOOL;
    _playground_schema_check BOOL;
    _next_id INTEGER;
    _dimension TEXT;
    _interval TEXT;
    _segmentby_cols TEXT;
    _orderby_cols TEXT;
BEGIN
    SELECT EXISTS(SELECT 1 FROM information_schema.schemata
    WHERE schema_name = 'tsdb_playground') INTO _playground_schema_check;

    IF NOT _playground_schema_check THEN
        RAISE EXCEPTION '"tsdb_playground" schema must be created before running this';
    END IF;

    -- get schema and table name
    SELECT n.nspname, c.relname INTO _schema_name, _table_name
    FROM pg_class c
    INNER JOIN pg_namespace n ON (n.oid = c.relnamespace)
    INNER JOIN timescaledb_information.hypertables i ON (i.hypertable_name = c.relname )
    WHERE c.oid = src_hypertable;

    IF _table_name IS NULL THEN
        RAISE EXCEPTION '% is not a hypertable', src_hypertable;
    END IF;

    SELECT EXISTS(SELECT 1 FROM timescaledb_information.chunks WHERE hypertable_name = _table_name AND hypertable_schema = _schema_name) INTO _chunk_check;

    IF NOT _chunk_check THEN
        RAISE EXCEPTION '% has no chunks for playground testing', src_hypertable;
    END IF;

    EXECUTE pg_catalog.format($$ CREATE SEQUENCE IF NOT EXISTS tsdb_playground.%I $$, _table_name||'_seq');
    SELECT pg_catalog.nextval('tsdb_playground.' || pg_catalog.quote_ident(_table_name || '_seq')) INTO _next_id;

    SELECT pg_catalog.format('%I.%I', _schema_name, _table_name) INTO _src_relation;

    SELECT pg_catalog.format('tsdb_playground.%I', _table_name || '_' || _next_id::text) INTO _playground_table_fqn;

    EXECUTE pg_catalog.format(
        $$ CREATE TABLE %s (like %s including comments including constraints including defaults including indexes) $$
        , _playground_table_fqn, _src_relation
        );

    -- get dimension column from src ht for partitioning playground ht
    SELECT column_name, time_interval INTO _dimension, _interval FROM timescaledb_information.dimensions WHERE hypertable_name = _table_name AND hypertable_schema = _schema_name LIMIT 1;

    PERFORM public.create_hypertable(_playground_table_fqn::REGCLASS, _dimension::NAME, chunk_time_interval := _interval::interval);

    -- Ideally, it should pick up the latest complete chunk (second last chunk) from this hypertable.
    -- If num_chunks > 1 then it will get true, converted into 1, taking the second row, otherwise it'll get false converted to 0 and get no offset.
    SELECT
        format('%I.%I',chunk_schema,chunk_name)
    INTO STRICT
        _chunk_name
    FROM
        timescaledb_information.chunks
    WHERE
        hypertable_schema = _schema_name AND
        hypertable_name = _table_name
    ORDER BY
        chunk_creation_time DESC OFFSET (
            SELECT
                (num_chunks > 1)::integer
            FROM timescaledb_information.hypertables
            WHERE
                hypertable_name = _table_name)
    LIMIT 1;
	EXECUTE pg_catalog.format($$ INSERT INTO %s SELECT * FROM %s $$, _playground_table_fqn, _chunk_name);

    IF compressed THEN
        --retrieve compression settings from source hypertable
        SELECT segmentby INTO _segmentby_cols
        FROM timescaledb_information.hypertable_compression_settings
        WHERE hypertable = _src_relation::REGCLASS;

		SELECT orderby INTO _orderby_cols
		FROM timescaledb_information.hypertable_compression_settings
        WHERE hypertable = _src_relation::REGCLASS;

        IF (_segmentby_cols IS NOT NULL) AND (_orderby_cols IS NOT NULL) THEN
            EXECUTE pg_catalog.format(
                $$ ALTER TABLE %s SET(timescaledb.compress, timescaledb.compress_segmentby = %I, timescaledb.compress_orderby = %I) $$
                , _playground_table_fqn, _segmentby_cols, _orderby_cols
                );
        ELSE
            EXECUTE pg_catalog.format(
                $$ ALTER TABLE %s SET(timescaledb.compress) $$
                , _playground_table_fqn
                );
        END IF;
        -- get playground chunk and compress
    PERFORM public.compress_chunk(public.show_chunks(_playground_table_fqn::REGCLASS));
    END IF;

	RETURN _playground_table_fqn;
END
$_$;


ALTER FUNCTION public.create_playground(src_hypertable regclass, compressed boolean) OWNER TO postgres;

SET default_tablespace = '';

SET default_table_access_method = heap;

--
-- TOC entry 264 (class 1259 OID 18813)
-- Name: flow; Type: TABLE; Schema: public; Owner: tsdbadmin
--

CREATE TABLE public.flow (
    device_id uuid NOT NULL,
    "timestamp" timestamp without time zone NOT NULL,
    temperature numeric,
    flow_lpm double precision,
    tdiff double precision,
    tdiff_moving_average1 double precision,
    tdiff_moving_average2 double precision,
    tdiff_moving_average3 double precision,
    package_count integer,
    outlier_count integer,
    volume_ml double precision DEFAULT 0.0,
    temperature_c double precision DEFAULT 0.0
);


ALTER TABLE public.flow OWNER TO tsdbadmin;

--
-- TOC entry 325 (class 1259 OID 32974)
-- Name: osm_chunk_1; Type: FOREIGN TABLE; Schema: _osm_tables; Owner: tsdbadmin
--

CREATE FOREIGN TABLE _osm_tables.osm_chunk_1 (
    device_id uuid,
    "timestamp" timestamp without time zone,
    temperature numeric,
    flow_lpm double precision,
    tdiff double precision,
    tdiff_moving_average1 double precision,
    tdiff_moving_average2 double precision,
    tdiff_moving_average3 double precision,
    package_count integer,
    outlier_count integer,
    volume_ml double precision DEFAULT 0.0,
    temperature_c double precision DEFAULT 0.0
)
INHERITS (public.flow)
SERVER s3_server
OPTIONS (
    table_id '1'
);


ALTER FOREIGN TABLE _osm_tables.osm_chunk_1 OWNER TO tsdbadmin;

--
-- TOC entry 265 (class 1259 OID 18824)
-- Name: tag; Type: TABLE; Schema: public; Owner: tsdbadmin
--

CREATE TABLE public.tag (
    id uuid NOT NULL,
    device_id uuid NOT NULL,
    "timestamp" timestamp without time zone NOT NULL,
    residence_fixture_id uuid,
    tag integer NOT NULL,
    annotation character varying(255),
    start_at timestamp without time zone,
    end_at timestamp without time zone,
    level integer DEFAULT 1,
    volume_l double precision DEFAULT 0.0,
    fixture_id uuid
);


ALTER TABLE public.tag OWNER TO tsdbadmin;

--
-- TOC entry 355 (class 1259 OID 37990)
-- Name: osm_chunk_2; Type: FOREIGN TABLE; Schema: _osm_tables; Owner: tsdbadmin
--

CREATE FOREIGN TABLE _osm_tables.osm_chunk_2 (
    id uuid,
    device_id uuid,
    "timestamp" timestamp without time zone,
    residence_fixture_id uuid,
    tag integer,
    annotation character varying(255),
    start_at timestamp without time zone,
    end_at timestamp without time zone,
    level integer DEFAULT 1,
    volume_l double precision DEFAULT 0.0,
    fixture_id uuid
)
INHERITS (public.tag)
SERVER s3_server
OPTIONS (
    table_id '2'
);


ALTER FOREIGN TABLE _osm_tables.osm_chunk_2 OWNER TO tsdbadmin;

--
-- TOC entry 267 (class 1259 OID 18842)
-- Name: zero; Type: TABLE; Schema: public; Owner: tsdbadmin
--

CREATE TABLE public.zero (
    device_id uuid NOT NULL,
    "timestamp" timestamp without time zone NOT NULL,
    tdiff double precision,
    temperature double precision,
    score double precision DEFAULT 0.0
);


ALTER TABLE public.zero OWNER TO tsdbadmin;

--
-- TOC entry 356 (class 1259 OID 37998)
-- Name: osm_chunk_4; Type: FOREIGN TABLE; Schema: _osm_tables; Owner: tsdbadmin
--

CREATE FOREIGN TABLE _osm_tables.osm_chunk_4 (
    device_id uuid,
    "timestamp" timestamp without time zone,
    tdiff double precision,
    temperature double precision,
    score double precision DEFAULT 0.0
)
INHERITS (public.zero)
SERVER s3_server
OPTIONS (
    table_id '4'
);


ALTER FOREIGN TABLE _osm_tables.osm_chunk_4 OWNER TO tsdbadmin;

--
-- TOC entry 269 (class 1259 OID 18857)
-- Name: inoson; Type: TABLE; Schema: public; Owner: tsdbadmin
--

CREATE TABLE public.inoson (
    device_id uuid NOT NULL,
    "timestamp" timestamp without time zone NOT NULL,
    status_int_flags bigint,
    tdiff integer,
    filter_tdiff integer,
    flow_rate integer,
    c bigint,
    temperature bigint,
    volume bigint,
    amplitude_up_2 bigint,
    amplitude_down_2 bigint,
    filter_amplitude_up bigint,
    filter_amplitude_down bigint,
    error_status integer,
    error_rate integer,
    filter_flow_rate integer
);


ALTER TABLE public.inoson OWNER TO tsdbadmin;

--
-- TOC entry 357 (class 1259 OID 38002)
-- Name: osm_chunk_5; Type: FOREIGN TABLE; Schema: _osm_tables; Owner: tsdbadmin
--

CREATE FOREIGN TABLE _osm_tables.osm_chunk_5 (
    device_id uuid,
    "timestamp" timestamp without time zone,
    status_int_flags bigint,
    tdiff integer,
    filter_tdiff integer,
    flow_rate integer,
    c bigint,
    temperature bigint,
    volume bigint,
    amplitude_up_2 bigint,
    amplitude_down_2 bigint,
    filter_amplitude_up bigint,
    filter_amplitude_down bigint,
    error_status integer,
    error_rate integer,
    filter_flow_rate integer
)
INHERITS (public.inoson)
SERVER s3_server
OPTIONS (
    table_id '5'
);


ALTER FOREIGN TABLE _osm_tables.osm_chunk_5 OWNER TO tsdbadmin;

--
-- TOC entry 270 (class 1259 OID 18864)
-- Name: statistic; Type: TABLE; Schema: public; Owner: tsdbadmin
--

CREATE TABLE public.statistic (
    device_id uuid NOT NULL,
    "timestamp" timestamp without time zone NOT NULL,
    field character varying(255),
    duration_usec bigint,
    count integer,
    min double precision,
    max double precision,
    mean double precision,
    median double precision,
    std_dev1 double precision,
    std_dev2 double precision,
    std_dev3 double precision,
    skewness double precision,
    kurtosis double precision
);


ALTER TABLE public.statistic OWNER TO tsdbadmin;
