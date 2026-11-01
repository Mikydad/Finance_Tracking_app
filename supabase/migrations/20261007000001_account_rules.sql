-- Merchant memory by account number: when the user picks a category on the
-- phone, it writes a rule for the counterparty's name and one for their masked
-- account (e.g. 2519****1122, ****3307), so the next SMS is categorized even
-- when the bank spells the name differently. The ingest categorizer checks the
-- account rule first.

alter table public.categorization_rules
  drop constraint categorization_rules_match_field_check;

alter table public.categorization_rules
  add constraint categorization_rules_match_field_check
  check (match_field in ('counterparty', 'counterparty_account', 'description'));
