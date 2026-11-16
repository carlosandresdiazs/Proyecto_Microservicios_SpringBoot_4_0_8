CREATE TABLE IF NOT EXISTS payments (
    id UUID PRIMARY KEY,
    user_id VARCHAR(150) NOT NULL,
    order_id VARCHAR(100) NOT NULL,
    amount NUMERIC(15,2) NOT NULL,
    currency VARCHAR(3) NOT NULL,
    status VARCHAR(24) NOT NULL,
    idempotency_key VARCHAR(120) NOT NULL,
    provider_reference VARCHAR(140),
    created_at TIMESTAMP(6) WITH TIME ZONE NOT NULL,
    updated_at TIMESTAMP(6) WITH TIME ZONE NOT NULL,
    CONSTRAINT uq_payments_user_idempotency UNIQUE (user_id, idempotency_key)
);
CREATE TABLE IF NOT EXISTS webhook_events (
    event_id VARCHAR(140) PRIMARY KEY,
    received_at TIMESTAMP(6) WITH TIME ZONE NOT NULL
);
