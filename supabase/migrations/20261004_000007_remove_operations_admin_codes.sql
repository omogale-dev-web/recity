-- Municipal access no longer uses a shared admin code.
-- Admin rights are granted only to a specific approved ReCity identity.
drop function if exists public.claim_operations_admin(text);
drop table if exists public.operations_admin_codes;
