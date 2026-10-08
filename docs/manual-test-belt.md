# Manual test belt

Run through this top to bottom against `pnpm dev` (http://localhost:5175) +
local Supabase. Check off what passes; note anything odd. Reset between full
runs with `supabase db reset` if you want a clean slate.

## 1. Auth

- [ ] Open the app signed out → sign-in page shows
- [ ] Enter an email → "link enviado" state, email lands in Mailpit (http://127.0.0.1:54324)
- [ ] Click the link → redirected back to the app, signed in
- [ ] Reload → still signed in (session persists)
- [ ] Sair → back to sign-in page
- [ ] Sign in again → still works

## 2. Open month

- [ ] Fresh user sees "Abrir {mês}" prompt
- [ ] Net income rejects junk: `abc`, `12,345`, empty
- [ ] Accepts `5000` and `5.000,00` equally → month opens, buckets = 50/30/20 of net
- [ ] Summary shows: Renda líquida, Total para gastar (net − invest), Investimento previsto, Restante = total para gastar

## 3. Categories

- [ ] "Gerenciar categorias" → add a category to Essencial (e.g. Mercado) and one to Lazer (e.g. Streaming)
- [ ] Same name twice in the same bucket → "Já existe uma categoria com esse nome"
- [ ] Same name in the OTHER bucket → allowed
- [ ] Archive a category → struck through in manager, gone from the entry form's select
- [ ] Unarchive → comes back

## 4. Entries

- [ ] "Lançar gasto" opens the sheet; empty category / bad amount rejected with messages
- [ ] Amount formats work: `25,90`, `25.90`, `1.250`, `1.250,00`
- [ ] Date outside the current month → rejected
- [ ] Entry appears under its category; count and sum update; bucket card Gasto/Restante update; summary Restante drops
- [ ] Overspend a bucket → Restante goes negative, progress bar red
- [ ] Expand a category → each entry listed; delete one → totals update
- [ ] Date input defaults to today

## 5. Month settings (Ajustar mês)

- [ ] Change net income → buckets and Restante recompute
- [ ] Apply a preset (e.g. 55/25/20) → buckets recompute
- [ ] Custom pcts that sum to ≠100 → "Os percentuais precisam somar 100", nothing saved
- [ ] pct > 100 or non-integer → rejected

## 6. Close month

- [ ] "Fechar mês" → dialog shows Investimento previsto, invested field prefilled
- [ ] Confirm → month badge flips to Fechado
- [ ] After close: no delete buttons on entries, no "Gerenciar categorias", no Ajustar/Fechar buttons, add-entry sheet says read-only
- [ ] History shows a row: month name, líquido, per-bucket rest, invested
- [ ] Reload → month stays closed
- [ ] "Reabrir mês" → confirm → month is open again: entries editable, settings/add back, history row gone
- [ ] Re-close the same month → new summary written with current entries

## 7. Month rollover & navigation

- [ ] Close the current month → ◀/▶ arrows in the summary card navigate months
- [ ] Navigate to a future month → "ainda não começou" message, no open form
- [ ] Navigate to a past month without a row → open form works (backfill)
- [ ] On a new calendar month → "Abrir {mês}" prompt; enter net → opens; recurring templates generate entries
- [ ] "Voltar para o mês atual" returns to the open month
- [ ] Navigate to a past closed month → read-only view of its entries
- [ ] Re-opening the app never duplicates entries (idempotent `open_month`)

## 7b. Stale session

- [ ] `pnpm supabase db reset` while signed in → open-month attempt shows the error with a hint and a Sair button
- [ ] Sair → sign in again → fresh account bootstraps (profile + settings recreated by trigger)

## 8. Multi-user (optional, second browser/incognito)

- [ ] Sign in as a different email → sees the "Abrir mês" prompt, not your data
- [ ] Categories/months are fully separate

## 9. Recorrentes & parcelas

- [ ] Recorrentes panel → Novo: name + value + category + day, parcelas empty → template appears, entry lands in the open month right away
- [ ] Novo with "Parcelas" = 3 and 1ª parcela = current month → template shows `1/3` badge, entry in the open month shows `1/3` on the row
- [ ] Bad input rejected: parcelas = 1, empty name, day 32, archived category absent from picker
- [ ] Cancel → badge shows "inativa", no more generation; Reativar resumes at the right parcela
- [ ] Open the next month when it arrives → next installment generated (e.g. `2/3`), unbounded templates generate again
- [ ] Delete a generated installment entry → plan badge unaffected; next month still generates the right index
- [ ] Archived category's template is skipped on `open_month` (covered by `supabase test db`)

## 10. Extras (extra income)

- [ ] Fun panel → "Adicionar extra": amount + date + note → row appears with `+R$` and fun card's Orçamento grows by that amount
- [ ] Summary card shows an "Extras" stat when extras exist; "Total para gastar" and "Restante do mês" include them
- [ ] Delete an extra → budget returns to the plain split
- [ ] Close the month → extras locked; history row shows "extras +R$ X" and fun budget includes them
- [ ] Reopen → extras editable/deletable again

## 11. Reservas & cofrinhos

- [ ] Reservas panel → Novo: name only → bank appears in the list with the switch on
- [ ] Reserva ativa card → the new bank shows; with 2+ active banks, ◀/▶ cycle through them (e.g. `1/2`)
- [ ] Depositar (+ icon): put 100 in Essencial only → a "Reservas" category appears in Essencial with the entry; Essencial Gasto rises 100; bank balance shows 100
- [ ] Depositar with a split (Essencial + Lazer) → one entry in each bucket, balance = the sum
- [ ] "Lançar gasto" → the bank's name appears under a Reservas optgroup; log an entry against it → it shows nowhere in Essencial/Lazer, appears in the Reserva ativa card, balance drops
- [ ] Try to log more than the bank has → rejected ("insufficient fund balance")
- [ ] Switch the bank off → it disappears from the add-entry select and the Reserva ativa card, stays in the Reservas list
- [ ] Delete a bank with a balance → dialog offers "move to extras of the current month": accept → extra appears in Extras (fun budget grows); decline → fund gone, money vanishes
- [ ] /cofrinhos → Novo: name + goal required; progress bar fills as deposits land; ✓ moves it to Concluídos (undo brings it back); delete offers the same extras transfer
- [ ] Deposit and entries on a closed month are rejected (read-only still holds)
