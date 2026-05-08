CREATE TABLE sync_cursor (
  cursor_name VARCHAR(100) PRIMARY KEY,
  last_synced_block BIGINT NOT NULL ,
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TABLE job_lock (
  job_name VARCHAR(100) PRIMARY KEY,
  locked_until TIMESTAMPTZ NOT NULL ,
  locked_by VARCHAR(255) NOT NULL ,
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TABLE job_run (
  id BIGSERIAL PRIMARY KEY,
  job_name VARCHAR(100) NOT NULL ,
  started_at TIMESTAMPTZ NOT NULL ,
  finished_at TIMESTAMPTZ,
  status VARCHAR(30) NOT NULL ,
  error_message TEXT,
  range_start_block BIGINT,
  range_end_block BIGINT
);

CREATE INDEX idx_job_run_name_started_at
  ON job_run (job_name, started_at DESC);

CREATE INDEX idx_job_run_status_started_at
  ON job_run (status, started_at DESC);


CREATE TABLE pending_tx (
  id BIGSERIAL PRIMARY KEY ,
  tx_hash VARCHAR(66) NOT NULL ,
  action_type VARCHAR(50) NOT NULL ,
  user_address VARCHAR(42) NOT NULL ,
  status VARCHAR(30) NOT NULL DEFAULT 'PENDING',
  submitted_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  CONSTRAINT uq_pending_tx_tx_hash UNIQUE (tx_hash)
);

CREATE INDEX idx_pending_tx_user_address_submitted_at
  ON pending_tx (user_address, submitted_at DESC);

CREATE INDEX idx_pending_tx_status_submitted_at
  ON pending_tx (status, submitted_at DESC );

CREATE TABLE raw_chain_event (
  id BIGSERIAL PRIMARY KEY ,
  event_name VARCHAR(100) NOT NULL ,
  tx_hash VARCHAR(66) NOT NULL,
  block_number BIGINT NOT NULL ,
  block_hash VARCHAR(66) NOT NULL ,
  log_index INTEGER NOT NULL ,
  contract_address VARCHAR(42) NOT NULL ,
  payload_json JSONB NOT NULL ,
  event_timestamp TIMESTAMPTZ NOT NULL ,
  removed BOOLEAN NOT NULL DEFAULT FALSE,
  CONSTRAINT uq_raw_chain_event_tx_hash_log_index UNIQUE (tx_hash, log_index)
);


CREATE INDEX idx_raw_chain_event_block_number_log_index
  ON raw_chain_event (block_number, log_index);

CREATE INDEX idx_raw_chain_event_event_name_block_number
  ON raw_chain_event (event_name, block_number);

CREATE INDEX idx_raw_chain_contract_address_block_number
  ON raw_chain_event (contract_address, block_number);

CREATE TABLE strategy_position (
                                 token_id BIGINT PRIMARY KEY,
                                 owner_address VARCHAR(42) NOT NULL,
                                 vault_address VARCHAR(42) NOT NULL,
                                 supply_asset VARCHAR(42) NOT NULL,
                                 borrow_asset VARCHAR(42) NOT NULL,
                                 is_open BOOLEAN NOT NULL,
                                 opened_block BIGINT NOT NULL,
                                 closed_block BIGINT,
                                 opened_tx_hash VARCHAR(66) NOT NULL,
                                 closed_tx_hash VARCHAR(66)
);

CREATE INDEX idx_strategy_position_owner_is_open
  ON strategy_position (owner_address, is_open);

CREATE INDEX idx_strategy_position_vault_is_open
  ON strategy_position (vault_address, is_open);

CREATE INDEX idx_strategy_position_is_open_opened_block
  ON strategy_position (is_open, opened_block DESC);

CREATE TABLE position_timeline (
                                 id BIGSERIAL PRIMARY KEY,
                                 token_id BIGINT NOT NULL,
                                 event_type VARCHAR(50) NOT NULL,
                                 tx_hash VARCHAR(66) NOT NULL,
                                 block_number BIGINT NOT NULL,
                                 event_timestamp TIMESTAMPTZ NOT NULL,
                                 user_address VARCHAR(42) NOT NULL,
                                 vault_address VARCHAR(42) NOT NULL,
                                 metadata_json JSONB NOT NULL DEFAULT '{}'::jsonb
);

CREATE INDEX idx_position_timeline_token_id_event_timestamp
  ON position_timeline (token_id, event_timestamp DESC);

CREATE INDEX idx_position_timeline_user_address_event_timestamp
  ON position_timeline (user_address, event_timestamp DESC);

CREATE INDEX idx_position_timeline_vault_address_event_timestamp
  ON position_timeline (vault_address, event_timestamp DESC);

CREATE TABLE pool_price_event (
                                id BIGSERIAL PRIMARY KEY,
                                pool_id TEXT NOT NULL,
                                tx_hash VARCHAR(66) NOT NULL,
                                block_number BIGINT NOT NULL,
                                log_index INTEGER NOT NULL,
                                tick INTEGER NOT NULL,
                                sqrt_price_x96 NUMERIC(78, 0) NOT NULL,
                                event_timestamp TIMESTAMPTZ NOT NULL,
                                CONSTRAINT uq_pool_price_event_tx_hash_log_index UNIQUE (tx_hash, log_index)
);

CREATE INDEX idx_pool_price_event_pool_id_event_timestamp
  ON pool_price_event (pool_id, event_timestamp DESC);

CREATE INDEX idx_pool_price_event_block_number
  ON pool_price_event (block_number DESC);

CREATE TABLE position_snapshot (
                                 id BIGSERIAL PRIMARY KEY,
                                 token_id BIGINT NOT NULL,
                                 owner_address VARCHAR(42) NOT NULL,
                                 vault_address VARCHAR(42) NOT NULL,
                                 supply_asset VARCHAR(42) NOT NULL,
                                 borrow_asset VARCHAR(42) NOT NULL,
                                 is_open BOOLEAN NOT NULL,
                                 liquidity NUMERIC(78, 0),
                                 amount0_now NUMERIC(78, 0),
                                 amount1_now NUMERIC(78, 0),
                                 current_tick INTEGER,
                                 sqrt_price_x96 NUMERIC(78, 0),
                                 total_collateral_base NUMERIC(78, 0),
                                 total_debt_base NUMERIC(78, 0),
                                 health_factor NUMERIC(38, 18),
                                 snapshot_at TIMESTAMPTZ NOT NULL,
                                 observed_block_number BIGINT NOT NULL,
                                 CONSTRAINT uq_position_snapshot_token_id_snapshot_at UNIQUE (token_id, snapshot_at)
);

CREATE INDEX idx_position_snapshot_token_id_snapshot_at
  ON position_snapshot (token_id, snapshot_at DESC);

CREATE INDEX idx_position_snapshot_snapshot_at
  ON position_snapshot (snapshot_at DESC);

CREATE TABLE user_vault (
                          id BIGSERIAL PRIMARY KEY,
                          user_address VARCHAR(42) NOT NULL,
                          vault_address VARCHAR(42) NOT NULL,
                          created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
                          CONSTRAINT uq_user_vault_vault_address UNIQUE (vault_address)
);

CREATE INDEX idx_user_vault_user_address
  ON user_vault (user_address);




