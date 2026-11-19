CREATE TABLE payments (
 id UUID PRIMARY KEY, user_id VARCHAR(150) NOT NULL, order_id VARCHAR(100) NOT NULL,
 amount NUMERIC(15,2) NOT NULL CHECK(amount > 0), currency CHAR(3) NOT NULL,
 status VARCHAR(24) NOT NULL CHECK(status IN ('PENDING','PAID','FAILED')),
 idempotency_key VARCHAR(120) NOT NULL, provider_reference VARCHAR(140),
 created_at TIMESTAMPTZ NOT NULL, updated_at TIMESTAMPTZ NOT NULL,
 CONSTRAINT uq_payment_user_key UNIQUE(user_id,idempotency_key)
);
CREATE UNIQUE INDEX ux_payment_provider_reference ON payments(provider_reference) WHERE provider_reference IS NOT NULL;
CREATE TABLE webhook_events(event_id VARCHAR(140) PRIMARY KEY,received_at TIMESTAMPTZ NOT NULL);
