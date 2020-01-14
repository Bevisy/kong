return {
  postgres = {
    up = [[
      CREATE TABLE IF NOT EXISTS "cluster_events" (
        "id"         UUID                       PRIMARY KEY,
        "node_id"    UUID                       NOT NULL,
        "at"         TIMESTAMP WITH TIME ZONE   NOT NULL,
        "nbf"        TIMESTAMP WITH TIME ZONE,
        "expire_at"  TIMESTAMP WITH TIME ZONE   NOT NULL,
        "channel"    TEXT,
        "data"       TEXT
      );

      CREATE INDEX IF NOT EXISTS "idx_cluster_events_at"      ON "cluster_events" ("at");
      CREATE INDEX IF NOT EXISTS "idx_cluster_events_channel" ON "cluster_events" ("channel");

      CREATE OR REPLACE FUNCTION "delete_expired_cluster_events" () RETURNS TRIGGER
      LANGUAGE plpgsql
      AS $$
        BEGIN
          DELETE FROM "cluster_events"
                WHERE "expire_at" <= CURRENT_TIMESTAMP AT TIME ZONE 'UTC';
          RETURN NEW;
        END;
      $$;

      DROP TRIGGER IF EXISTS "delete_expired_cluster_events_trigger" ON "cluster_events";
      CREATE TRIGGER "delete_expired_cluster_events_trigger"
        AFTER INSERT ON "cluster_events"
        FOR EACH STATEMENT
        EXECUTE PROCEDURE delete_expired_cluster_events();



      CREATE TABLE IF NOT EXISTS "services" (
        "id"               UUID                       PRIMARY KEY,
        "created_at"       TIMESTAMP WITH TIME ZONE,
        "updated_at"       TIMESTAMP WITH TIME ZONE,
        "name"             TEXT                       UNIQUE,
        "retries"          BIGINT,
        "protocol"         TEXT,
        "host"             TEXT,
        "port"             BIGINT,
        "path"             TEXT,
        "connect_timeout"  BIGINT,
        "write_timeout"    BIGINT,
        "read_timeout"     BIGINT
      );



      CREATE TABLE IF NOT EXISTS "routes" (
        "id"              UUID                       PRIMARY KEY,
        "created_at"      TIMESTAMP WITH TIME ZONE,
        "updated_at"      TIMESTAMP WITH TIME ZONE,
        "service_id"      UUID                       REFERENCES "services" ("id"),
        "protocols"       TEXT[],
        "methods"         TEXT[],
        "hosts"           TEXT[],
        "paths"           TEXT[],
        "regex_priority"  BIGINT,
        "strip_path"      BOOLEAN,
        "preserve_host"   BOOLEAN

      );

      CREATE INDEX IF NOT EXISTS "routes_fkey_service" ON "routes" ("service_id");



      CREATE TABLE IF NOT EXISTS "apis" (
        "id"                        UUID                         PRIMARY KEY,
        "created_at"                TIMESTAMP WITHOUT TIME ZONE  DEFAULT (CURRENT_TIMESTAMP(3) AT TIME ZONE 'UTC'),
        "name"                      TEXT                         UNIQUE,
        "upstream_url"              TEXT,
        "preserve_host"             BOOLEAN                      NOT NULL,
        "retries"                   SMALLINT                     DEFAULT 5,
        "https_only"                BOOLEAN,
        "http_if_terminated"        BOOLEAN,
        "hosts"                     TEXT,
        "uris"                      TEXT,
        "methods"                   TEXT,
        "strip_uri"                 BOOLEAN,
        "upstream_connect_timeout"  INTEGER,
        "upstream_send_timeout"     INTEGER,
        "upstream_read_timeout"     INTEGER
      );



      CREATE TABLE IF NOT EXISTS "certificates" (
        "id"          UUID                       PRIMARY KEY,
        "created_at"  TIMESTAMP WITH TIME ZONE   DEFAULT (CURRENT_TIMESTAMP(0) AT TIME ZONE 'UTC'),
        "cert"        TEXT,
        "key"         TEXT
      );



      CREATE TABLE IF NOT EXISTS "snis" (
        "id"              UUID                       PRIMARY KEY,
        "created_at"      TIMESTAMP WITH TIME ZONE   DEFAULT (CURRENT_TIMESTAMP(0) AT TIME ZONE 'UTC'),
        "name"            TEXT                       NOT NULL UNIQUE,
        "certificate_id"  UUID                       REFERENCES "certificates" ("id")
      );


      CREATE TABLE IF NOT EXISTS "consumers" (
        "id"          UUID                         PRIMARY KEY,
        "created_at"  TIMESTAMP WITHOUT TIME ZONE  DEFAULT (CURRENT_TIMESTAMP(0) AT TIME ZONE 'UTC'),
        "username"    TEXT                         UNIQUE,
        "custom_id"   TEXT                         UNIQUE
      );

      CREATE INDEX IF NOT EXISTS "username_idx" ON "consumers" (LOWER("username"));



      CREATE TABLE IF NOT EXISTS "plugins" (
        "id"           UUID                         UNIQUE,
        "created_at"   TIMESTAMP WITHOUT TIME ZONE  DEFAULT (CURRENT_TIMESTAMP(0) AT TIME ZONE 'UTC'),
        "name"         TEXT                         NOT NULL,
        "consumer_id"  UUID                         REFERENCES "consumers" ("id") ON DELETE CASCADE,
        "service_id"   UUID                         REFERENCES "services"  ("id") ON DELETE CASCADE,
        "route_id"     UUID                         REFERENCES "routes"    ("id") ON DELETE CASCADE,
        "api_id"       UUID                         REFERENCES "apis"      ("id") ON DELETE CASCADE,
        "config"       JSON                         NOT NULL,
        "enabled"      BOOLEAN                      NOT NULL,

        PRIMARY KEY ("id", "name")
      );

      CREATE INDEX IF NOT EXISTS "plugins_name_idx"       ON "plugins" ("name");
      CREATE INDEX IF NOT EXISTS "plugins_consumer_idx"   ON "plugins" ("consumer_id");
      CREATE INDEX IF NOT EXISTS "plugins_service_id_idx" ON "plugins" ("service_id");
      CREATE INDEX IF NOT EXISTS "plugins_route_id_idx"   ON "plugins" ("route_id");
      CREATE INDEX IF NOT EXISTS "plugins_api_idx"        ON "plugins" ("api_id");



      CREATE TABLE IF NOT EXISTS "upstreams" (
        "id"                    UUID                         PRIMARY KEY,
        "created_at"            TIMESTAMP WITHOUT TIME ZONE  DEFAULT (CURRENT_TIMESTAMP(3) AT TIME ZONE 'UTC'),
        "name"                  TEXT                         UNIQUE,
        "hash_on"               TEXT,
        "hash_fallback"         TEXT,
        "hash_on_header"        TEXT,
        "hash_fallback_header"  TEXT,
        "hash_on_cookie"        TEXT,
        "hash_on_cookie_path"   TEXT,
        "slots"                 INTEGER                      NOT NULL,
        "healthchecks"          JSON
      );



      CREATE TABLE IF NOT EXISTS "targets" (
        "id"           UUID                         PRIMARY KEY,
        "created_at"   TIMESTAMP WITHOUT TIME ZONE  DEFAULT (CURRENT_TIMESTAMP(3) AT TIME ZONE 'UTC'),
        "upstream_id"  UUID                         REFERENCES "upstreams" ("id") ON DELETE CASCADE,
        "target"       TEXT                         NOT NULL,
        "weight"       INTEGER                      NOT NULL
      );

      CREATE INDEX IF NOT EXISTS "targets_target_idx" ON "targets" ("target");



      -- TODO: delete on 1.0.0 migrations
      CREATE TABLE IF NOT EXISTS "ttls" (
        "primary_key_value"  TEXT                         NOT NULL,
        "primary_uuid_value" UUID,
        "table_name"         TEXT                         NOT NULL,
        "primary_key_name"   TEXT                         NOT NULL,
        "expire_at"          TIMESTAMP WITHOUT TIME ZONE  NOT NULL,

        PRIMARY KEY ("primary_key_value", "table_name")
      );

      CREATE INDEX IF NOT EXISTS "ttls_primary_uuid_value_idx" ON "ttls" ("primary_uuid_value");

      CREATE OR REPLACE FUNCTION "upsert_ttl" (v_primary_key_value TEXT, v_primary_uuid_value UUID, v_primary_key_name TEXT, v_table_name TEXT, v_expire_at TIMESTAMP WITHOUT TIME ZONE) RETURNS void
      LANGUAGE plpgsql
      AS $$
        BEGIN
          LOOP
            UPDATE ttls
               SET expire_at = v_expire_at
             WHERE primary_key_value = v_primary_key_value
               AND table_name = v_table_name;

            IF FOUND then
              RETURN;
            END IF;

            BEGIN
              INSERT INTO ttls (primary_key_value, primary_uuid_value, primary_key_name, table_name, expire_at)
                   VALUES (v_primary_key_value, v_primary_uuid_value, v_primary_key_name, v_table_name, v_expire_at);
              RETURN;
            EXCEPTION WHEN unique_violation THEN

            END;
          END LOOP;
        END;
        $$;
    ]]
  },

  cassandra = {
    up = [[
      CREATE TABLE IF NOT EXISTS cluster_events(
        channel text,
        at      timestamp,
        node_id uuid,
        id      uuid,
        data    text,
        nbf     timestamp,
        PRIMARY KEY (channel, at, node_id, id)
      ) WITH default_time_to_live = 86400;



      CREATE TABLE IF NOT EXISTS services(
        partition       text,
        id              uuid,
        created_at      timestamp,
        updated_at      timestamp,
        name            text,
        host            text,
        path            text,
        port            int,
        protocol        text,
        connect_timeout int,
        read_timeout    int,
        write_timeout   int,
        retries         int,
        PRIMARY KEY     (partition, id)
      );
      CREATE INDEX IF NOT EXISTS services_name_idx ON services(name);



      CREATE TABLE IF NOT EXISTS routes(
        partition      text,
        id             uuid,
        created_at     timestamp,
        updated_at     timestamp,
        hosts          list<text>,
        paths          list<text>,
        methods        set<text>,
        protocols      set<text>,
        preserve_host  boolean,
        strip_path     boolean,
        service_id     uuid,
        regex_priority int,
        PRIMARY KEY    (partition, id)
      );
      CREATE INDEX IF NOT EXISTS routes_service_id_idx ON routes(service_id);



      CREATE TABLE IF NOT EXISTS snis(
        partition          text,
        id                 uuid,
        name               text,
        certificate_id     uuid,
        created_at         timestamp,
        PRIMARY KEY        (partition, id)
      );
      CREATE INDEX IF NOT EXISTS snis_name_idx ON snis(name);
      CREATE INDEX IF NOT EXISTS snis_certificate_id_idx
        ON snis(certificate_id);



      CREATE TABLE IF NOT EXISTS certificates(
        partition text,
        id uuid,
        cert text,
        key text,
        created_at timestamp,
        PRIMARY KEY (partition, id)
      );



      CREATE TABLE IF NOT EXISTS consumers(
        id uuid    PRIMARY KEY,
        created_at timestamp,
        username   text,
        custom_id  text
      );
      CREATE INDEX IF NOT EXISTS consumers_username_idx ON consumers(username);
      CREATE INDEX IF NOT EXISTS consumers_custom_id_idx ON consumers(custom_id);



      CREATE TABLE IF NOT EXISTS plugins(
        id          uuid,
        name        text,
        api_id      uuid,
        config      text,
        consumer_id uuid,
        created_at  timestamp,
        enabled     boolean,
        route_id    uuid,
        service_id  uuid,
        PRIMARY KEY (id, name)
      );
      CREATE INDEX IF NOT EXISTS plugins_name_idx ON plugins(name);
      CREATE INDEX IF NOT EXISTS plugins_api_id_idx ON plugins(api_id);
      CREATE INDEX IF NOT EXISTS plugins_route_id_idx ON plugins(route_id);
      CREATE INDEX IF NOT EXISTS plugins_service_id_idx ON plugins(service_id);
      CREATE INDEX IF NOT EXISTS plugins_consumer_id_idx ON plugins(consumer_id);



      CREATE TABLE IF NOT EXISTS upstreams(
        id                   uuid PRIMARY KEY,
        created_at           timestamp,
        hash_fallback        text,
        hash_fallback_header text,
        hash_on              text,
        hash_on_cookie       text,
        hash_on_cookie_path  text,
        hash_on_header       text,
        healthchecks         text,
        name                 text,
        slots                int
      );
      CREATE INDEX IF NOT EXISTS upstreams_name_idx ON upstreams(name);



      CREATE TABLE IF NOT EXISTS targets(
        id          uuid PRIMARY KEY,
        created_at  timestamp,
        target      text,
        upstream_id uuid,
        weight      int
      );
      CREATE INDEX IF NOT EXISTS targets_upstream_id_idx ON targets(upstream_id);
      CREATE INDEX IF NOT EXISTS targets_target_idx ON targets(target);



      CREATE TABLE IF NOT EXISTS apis(
        id                       uuid PRIMARY KEY,
        created_at               timestamp,
        hosts                    text,
        http_if_terminated       boolean,
        https_only               boolean,
        methods                  text,
        name                     text,
        preserve_host            boolean,
        retries                  int,
        strip_uri                boolean,
        upstream_connect_timeout int,
        upstream_read_timeout    int,
        upstream_send_timeout    int,
        upstream_url             text,
        uris                     text
      );
      CREATE INDEX IF NOT EXISTS apis_name_idx ON apis(name);
    ]],
  },
  mysql = {
    up = [[
      CREATE TABLE `cluster_events` (
      `id` varchar(50) PRIMARY KEY,
      `node_id` varchar(50) NOT NULL,
      `at` timestamp NOT NULL,
      `nbf` timestamp,
      `expire_at` timestamp NOT NULL,
      `channel` varchar(512),
      `data` text,
      INDEX idx_cluster_events_at (`at`),
      INDEX idx_cluster_events_channel (`channel`)
      ) ENGINE=INNODB DEFAULT CHARSET=utf8;

      -- ----------------------------
      -- Function structure for delete_expired_cluster_events
      -- ----------------------------
      -- DROP PROCEDURE
      -- IF EXISTS delete_expired_cluster_events;
      -- delimiter //
      --
      -- CREATE PROCEDURE delete_expired_cluster_events (
      --         IN p_dnname text,
      --         IN p_tablename text,
      --         IN p_column text
      -- )
      -- BEGIN
      --         DECLARE str text ;
      --         SET @str = concat(
      --                 ' DELETE FROM ',
      --                 p_dbname,
      --         '.',
      --         p_tablename,
      --                 ' WHERE ',
      --                 p_column,
      --                 ' <= CURRENT_TIMESTAMP()'
      --         );
      --         SELECT
      --                 count(*) INTO @cnt
      --         FROM
      --                 information_schema.`COLUMNS`
      --         WHERE
      --                 TABLE_SCHEMA = p_dbname
      --                AND TABLE_NAME = p_tablename
      --                AND COLUMN_NAME = p_column ;
      --
      --         IF @cnt > 0 THEN
      --                 PREPARE stmt  FROM  @str ;
      --                 EXECUTE stmt ;
      --                 DROP PREPARE stmt ;
      --         END IF ;
      -- END;
      -- //
      -- delimiter ;
      --
      -- DROP TRIGGER
      -- IF EXISTS delete_expired_cluster_events_trigger;
      -- CREATE TRIGGER delete_expired_cluster_events_trigger AFTER INSERT ON cluster_events
      -- FOR EACH ROW
      -- CALL delete_expired_cluster_events();


      CREATE TABLE `services` (
      `id` varchar(50) PRIMARY KEY,
      `created_at` timestamp,
      `updated_at` timestamp,
      `name` text,
      `retries` int8,
      `protocol` text ,
      `host` text ,
      `port` int8,
      `path` text ,
      `connect_timeout` int8,
      `write_timeout` int8,
      `read_timeout` int8
      ) ENGINE=INNODB DEFAULT CHARSET=utf8;

      -- ----------------------------
      -- Uniques structure for table services
      -- ----------------------------
      ALTER TABLE services ADD CONSTRAINT services_name_key UNIQUE (`name`(50));


      CREATE TABLE `routes` (
      `id` varchar(50) PRIMARY KEY,
      `created_at` timestamp,
      `updated_at` timestamp,
      `service_id` varchar(50),
      `protocols` text,-- #Becareful it is text[] format
      `methods` text,-- #Becareful it is text[] format
      `hosts` text,-- #Becareful it is text[] format
      `paths` text,-- #Becareful it is text[] format
      `regex_priority` int8,
      `strip_path` bool,
      `preserve_host` bool,
      `name` text ,
      `snis` text ,-- #Becareful it is text[] format
      `sources` text,-- #Becareful it is jsonb[] format
      `destinations` text,-- #Becareful it is jsonb[] format
      FOREIGN KEY (`service_id`) REFERENCES `services`(`id`) ON DELETE CASCADE
      ) ENGINE=INNODB DEFAULT CHARSET=utf8;

      -- ----------------------------
      -- Indexes structure for table routes
      -- ----------------------------
      CREATE INDEX routes_service_id_idx ON routes  (`service_id`);

      -- ----------------------------
      -- Uniques structure for table routes
      -- ----------------------------
      ALTER TABLE routes ADD CONSTRAINT routes_name_key UNIQUE (`name`(50));

      -- ----------------------------
      -- Foreign Keys structure for table routes
      -- ----------------------------
      ALTER TABLE routes ADD CONSTRAINT routes_service_id_fkey FOREIGN KEY (`service_id`) REFERENCES services (`id`) ON DELETE CASCADE;


      CREATE TABLE `apis` (
      `id` varchar(50) PRIMARY KEY,
      `created_at` timestamp NOT NULL,
      `name` text ,
      `upstream_url` text ,
      `preserve_host` bool NOT NULL,
      `retries` int2 DEFAULT 5,
      `https_only` bool,
      `http_if_terminated` bool,
      `hosts` text,
      `uris` text,
      `methods` text,
      `strip_uri` bool,
      `upstream_connect_timeout` int4,
      `upstream_send_timeout` int4,
      `upstream_read_timeout` int4
      ) ENGINE=INNODB DEFAULT CHARSET=utf8;

      -- ----------------------------
      -- Uniques structure for table apis
      -- ----------------------------
      ALTER TABLE apis ADD CONSTRAINT apis_name_key UNIQUE (`name`(50));


      CREATE TABLE `certificates` (
      `id` varchar(50) PRIMARY KEY,
      `created_at` timestamp NOT NULL,
      `cert` text ,
      `key` text
      ) ENGINE=INNODB DEFAULT CHARSET=utf8;


      CREATE TABLE `snis` (
      `id` varchar(50) PRIMARY KEY,
      `created_at` timestamp NOT NULL,
      `name` text  NOT NULL,
      `certificate_id` varchar(50)
      ) ENGINE=INNODB DEFAULT CHARSET=utf8;

      -- ----------------------------
      -- Indexes structure for table snis
      -- ----------------------------
      CREATE INDEX snis_certificate_id_idx ON snis  (`certificate_id`);

      -- ----------------------------
      -- Uniques structure for table snis
      -- ----------------------------
      ALTER TABLE snis ADD CONSTRAINT snis_name_key UNIQUE (`name`(50));

      -- ----------------------------
      -- Foreign Keys structure for table snis
      -- ----------------------------
      ALTER TABLE snis ADD CONSTRAINT snis_certificate_id_fkey FOREIGN KEY (`certificate_id`) REFERENCES certificates (`id`) ON DELETE CASCADE;


      CREATE TABLE `consumers` (
      `id` varchar(50) PRIMARY KEY,
      `created_at` timestamp NOT NULL,
      `username` text ,
      `custom_id` text
      ) ENGINE=INNODB DEFAULT CHARSET=utf8;

      -- ----------------------------
      -- Indexes structure for table consumers
      -- ----------------------------
      CREATE INDEX consumers_username_idx ON consumers  (`username`(50));

      -- ----------------------------
      -- Uniques structure for table consumers
      -- ----------------------------
      ALTER TABLE consumers ADD CONSTRAINT consumers_username_key UNIQUE (`username`(50));
      ALTER TABLE consumers ADD CONSTRAINT consumers_custom_id_key UNIQUE (`custom_id`(50));


      CREATE TABLE `plugins` (
      `id` varchar(50) PRIMARY KEY,
      `created_at` timestamp NOT NULL,
      `name` text  NOT NULL,
      `consumer_id` varchar(50),
      `service_id` varchar(50),
      `route_id` varchar(50),
      `api_id` varchar(50),
      `config` text NOT NULL, -- #Becareful it is jsonb format
      `enabled` bool NOT NULL,
      `cache_key` text ,
      `run_on` text ,
      FOREIGN KEY (`consumer_id`) REFERENCES `consumers`(`id`) ON DELETE CASCADE,
      FOREIGN KEY (`service_id`) REFERENCES `services`(`id`) ON DELETE CASCADE,
      FOREIGN KEY (`route_id`) REFERENCES `routes`(`id`) ON DELETE CASCADE,
      FOREIGN KEY (`api_id`) REFERENCES `apis`(`id`) ON DELETE CASCADE
      ) ENGINE=INNODB DEFAULT CHARSET=utf8;

      -- ----------------------------
      -- Indexes structure for table plugins
      -- ----------------------------
      CREATE INDEX plugins_api_id_idx ON plugins  (`api_id`);
      CREATE INDEX plugins_consumer_id_idx ON plugins  (`consumer_id`);
      CREATE INDEX plugins_name_idx ON plugins  (`name`(50));
      CREATE INDEX plugins_route_id_idx ON plugins  (`route_id`);
      CREATE INDEX plugins_run_on_idx ON plugins  (`run_on`(50));
      CREATE INDEX plugins_service_id_idx ON plugins  (`service_id`);

      -- ----------------------------
      -- Uniques structure for table plugins
      -- ----------------------------
      ALTER TABLE plugins ADD CONSTRAINT plugins_cache_key_key UNIQUE (`cache_key`(50));


      -- ----------------------------
      -- Foreign Keys structure for table plugins
      -- ----------------------------
      ALTER TABLE plugins ADD CONSTRAINT plugins_api_id_fkey FOREIGN KEY (`api_id`) REFERENCES apis (`id`) ON DELETE CASCADE;
      ALTER TABLE plugins ADD CONSTRAINT plugins_consumer_id_fkey FOREIGN KEY (`consumer_id`) REFERENCES consumers (`id`) ON DELETE CASCADE;
      ALTER TABLE plugins ADD CONSTRAINT plugins_route_id_fkey FOREIGN KEY (`route_id`) REFERENCES routes (`id`) ON DELETE CASCADE;
      ALTER TABLE plugins ADD CONSTRAINT plugins_service_id_fkey FOREIGN KEY (`service_id`) REFERENCES services (`id`) ON DELETE CASCADE;


      CREATE TABLE `upstreams` (
      `id` varchar(50) PRIMARY KEY,
      `created_at` timestamp NOT NULL,
      `name` text ,
      `hash_on` text ,
      `hash_fallback` text ,
      `hash_on_header` text ,
      `hash_fallback_header` text ,
      `hash_on_cookie` text ,
      `hash_on_cookie_path` text ,
      `slots` int4 NOT NULL,
      `healthchecks` text -- #Becareful it is jsonb format
      ) ENGINE=INNODB DEFAULT CHARSET=utf8;

      -- ----------------------------
      -- Uniques structure for table upstreams
      -- ----------------------------
      ALTER TABLE upstreams ADD CONSTRAINT upstreams_name_key UNIQUE (`name`(50));


      CREATE TABLE `targets` (
      `id` varchar(50) PRIMARY KEY,
      `created_at` timestamp NOT NULL,
      `upstream_id` varchar(50),
      `target` text  NOT NULL,
      `weight` int4 NOT NULL,
      FOREIGN KEY (`upstream_id`) REFERENCES `upstreams`(`id`) ON DELETE CASCADE
      ) ENGINE=INNODB DEFAULT CHARSET=utf8;

      -- ----------------------------
      -- Indexes structure for table targets
      -- ----------------------------
      CREATE INDEX targets_target_idx ON targets  (`target`(50));
      CREATE INDEX targets_upstream_id_idx ON targets  (`upstream_id`);

      -- ----------------------------
      -- Foreign Keys structure for table targets
      -- ----------------------------
      ALTER TABLE targets ADD CONSTRAINT targets_upstream_id_fkey FOREIGN KEY (`upstream_id`) REFERENCES upstreams (`id`) ON DELETE CASCADE;


      CREATE TABLE `ttls` (
      `primary_key_value` varchar(200)  NOT NULL,
      `primary_uuid_value` varchar(50),
      `table_name` varchar(100)  NOT NULL,
      `primary_key_name` varchar(100)  NOT NULL,
      `expire_at` timestamp NOT NULL,
      PRIMARY KEY(`primary_key_value`, `table_name`),
      INDEX `ttls_primary_uuid_value_idx` (`primary_uuid_value`)
      ) ENGINE=INNODB DEFAULT CHARSET=utf8;


      CREATE TABLE `cluster_ca` (
      `pk` bool NOT NULL PRIMARY KEY CHECK(pk=true),
      `key` text NOT NULL,
      `cert` text NOT NULL
      ) ENGINE=INNODB DEFAULT CHARSET=utf8;
    ]]
  },
}
