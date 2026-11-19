WARUNG DARUL ILMI - MIGRATION ORDER (AUDIT)

SOURCE FILES IN BRANCH app:
- warung-darul-ilmi-database-v1.sql
- migration-v2-guest-checkout.sql
- migration-v3-operations-security.sql
- migration-v4-whatsapp-routing.sql
- migration-v5-cashier-scope-hardening.sql
- warung-darul-ilmi-fix-order-history-trigger.sql

CURRENT supabase/migrations:
- 202611180001_secure_store_settings.sql
- 202611180002_store_brand_logo.sql
- 202611180003_align_guest_checkout_rpc.sql

FINDING:
The first five database setup files are outside supabase/migrations. A new Supabase project will not receive them through `supabase db push`.

WHY THEY ARE NOT AUTOMATICALLY MOVED INTO THE MIGRATION FOLDER:
The current production database was created through a mixture of SQL Editor migrations and CLI migration pushes. Moving old SQL files into the folder and running `db push` would risk replaying non-idempotent DDL and policies, while migration history could diverge from the actual schema.

SAFE NEXT STEP:
For a NEW empty Supabase project:
- Build a reviewed baseline from a schema-only dump of the intended current database state.
- Start a fresh migration history from that baseline.

For the EXISTING production project:
- First capture `npx supabase migration list --remote`.
- Compare the actual schema with the migration files.
- Only then baseline/stamp existing migrations. Do not rerun v1-v5.

The two approaches need separate workflows. This guide intentionally contains no destructive SQL.
