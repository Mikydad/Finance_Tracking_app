# Finance App — V1 PRD

## 1. Product Overview

### Working concept

A simple personal finance app that automatically captures and organizes a user's financial transactions, helping them understand where their money goes without requiring them to manually record every expense.

### V1 goal

Make expense tracking almost effortless.

The user should be able to:

1. Connect transaction sources.
2. Automatically detect transactions.
3. Review and correct them.
4. Add manual transactions when necessary.
5. Categorize spending.
6. Search and understand their spending.
7. See their financial history.

### V1 positioning

Know where your money goes.

Not a complicated budgeting app.
Not an investment platform.
Not accounting software.

A financial memory.

## 2. Core User Problem

Most people don't consistently record expenses because manual tracking is annoying.

A user might spend:

* 500 ETB on lunch
* 1,200 ETB on transportation
* 3,500 ETB on shopping
* 800 ETB helping a friend
* 2,000 ETB on something they can't remember

A few weeks later:

“Where did all my money go?”

The app should answer that question automatically.

## 3. V1 Scope

### In scope

#### Transaction capture

* Bank/SMS transaction detection
* iPhone Shortcut-based capture
* Manual transaction entry
* Incoming and outgoing transactions

#### Transaction processing

* Amount extraction
* Currency extraction
* Date/time extraction
* Merchant/person extraction
* Transaction type
* Categorization
* Duplicate detection
* Confidence score

#### Personal finance

* Transaction history
* Categories
* Spending summaries
* Search
* Filters
* Monthly overview

#### Data

* Local-first storage
* Cloud synchronization
* Transaction history
* User corrections

### Not in V1

* Business/team accounts
* Shared transactions
* Merchant accounts
* Team members
* Business dashboards
* Invoicing
* Accounting
* Investments
* Loans
* Complex budgeting
* Bank API integrations
* Payments

## 4. The Most Important Architectural Decision

The core entity should be:

`Transaction`

Everything else should build around it.

Don't make the architecture:

Expense → category → user

Instead:

Financial Account / Source → Transaction → Classification → Insights

This will make future business functionality much easier.

## 5. Core Data Model

### User

```
User
- id
- name
- email
- phone
- defaultCurrency
- timezone
- createdAt
- updatedAt
```

### Transaction

```
Transaction
- id
- userId

- type
  - expense
  - income
  - transfer

- amount
- currency

- occurredAt

- merchantName
- counterpartyName

- categoryId

- sourceId

- description

- referenceId

- rawData

- status
  - pending
  - confirmed
  - needs_review

- confidenceScore

- createdAt
- updatedAt
```

### Why `counterpartyName`?

Don't hardcode the concept of "merchant."

A transaction could be:

500 ETB → Restaurant

or:

2,000 ETB → Abebe

or:

10,000 ETB → Bank Account

That distinction becomes important later for the business system.

## 6. Transaction Source

Create this abstraction from V1.

```
TransactionSource
- id
- userId

- type
  - manual
  - sms
  - shortcut
  - bank
  - other

- provider
- identifier

- metadata

- isActive

- createdAt
```

For V1, you might have:

```
manual
shortcut
sms
```

Later:

```
bank_api
telebirr
merchant_account
business_account
```

You don't need to implement those now.

Just make the architecture capable of supporting them.

## 7. Transaction Ingestion Pipeline

This should be one of the most important pieces of the backend.

```
Transaction Source
        ↓
Ingestion
        ↓
Parser
        ↓
Normalizer
        ↓
Duplicate Detection
        ↓
Categorization
        ↓
Confidence
        ↓
Transaction
        ↓
User
```

For example:

### Raw input

```
CBE:
Your account 1234 has been debited
by ETB 2,500.00 at ABC SHOP.
Available balance...
```

### Parser

Extract:

```
{
  "amount": 2500,
  "currency": "ETB",
  "type": "expense",
  "merchant": "ABC SHOP"
}
```

### Normalizer

```
ABC SHOP
↓
Abc Shop
```

### Categorizer

```
ABC Shop
↓
Shopping
```

### Final transaction

```
Expense
2,500 ETB
ABC Shop
Shopping
Today 14:32
```

## 8. Parser Architecture

Do not put bank-specific parsing logic everywhere.

Use a parser interface.

```
TransactionParser
```

Then:

```
CBEParser
AwashParser
DashenParser
TelebirrParser
GenericParser
```

Each parser converts its input into the same normalized transaction structure.

This is important because Ethiopian financial SMS formats will differ.

## 9. iPhone Architecture

For iPhone:

```
Bank SMS
    ↓
iOS Shortcut
    ↓
Keyword detection
    ↓
Finance API
    ↓
Transaction ingestion pipeline
```

The Shortcut can initially look for keywords such as:

```
ETB
Birr
debited
credited
transferred
balance
```

But don't rely entirely on keywords inside the backend architecture.

The Shortcut is simply an input source.

The backend should still validate and parse the message.

## 10. Android Architecture

Later:

```
Bank SMS
    ↓
Android SMS listener
    ↓
Finance app
    ↓
Transaction ingestion
```

The backend should receive the same normalized input regardless of platform.

Therefore:

```
iPhone Shortcut ──┐
                  │
Android SMS ──────┼──> Transaction Ingestion
                  │
Manual Entry ─────┘
```

This is a very important separation.

## 11. Manual Transactions

Automation won't catch everything.

The user should always be able to add:

### Add transaction

```
Amount
1,500 ETB

Type
Expense

Where?
ABC Restaurant

Category
Food

Date
Today

Notes
Dinner with friends
```

Keep this extremely fast.

Ideally:

Amount → category → done

Everything else should be optional.

## 12. Categories

Start with a simple category system.

### Default categories

Food

* Restaurants
* Groceries
* Coffee

Transport

* Taxi
* Fuel
* Public transport

Shopping

Bills

* Internet
* Phone
* Electricity

Entertainment

Health

Education

Family

Subscriptions

Other

Users can create custom categories later.

## 13. Categorization Engine

Initially:

```
Merchant
+
Transaction description
+
Historical user corrections
↓
Category
```

Example:

```
MERON CAFE
↓
Food
```

If the user changes it:

```
MERON CAFE
Food → Business
```

The system should remember that correction.

Eventually:

```
Merchant history
+
User behavior
+
AI classification
↓
Personalized category
```

This makes the app smarter over time.

## 14. Duplicate Detection

This is extremely important with automated ingestion.

The same transaction might arrive through:

* SMS
* Shortcut
* manual entry
* future bank API

You don't want:

−2,500 ETB

appearing three times.

Create a transaction fingerprint using things such as:

```
source
amount
timestamp
referenceId
counterparty
```

Then:

```
Incoming transaction
       ↓
Already exists?
    ↙       ↘
  Yes        No
   ↓          ↓
Ignore      Create
```

## 15. Transaction Review

Sometimes the parser won't know exactly what something means.

Example:

−1,200 ETB
MERON

The app can show:

Needs review

What was this?

Food
Shopping
Transport
Other

After the user answers, the system remembers.

This is important because the user should correct the system rather than manually enter everything.

## 16. Home Screen

The V1 home screen should answer:

Where is my money going?

Something like:

```
Good evening

October

Spent
18,450 ETB

Income
42,000 ETB

────────────────

This month

Food          4,250
Transport     2,100
Shopping      5,600
Bills         3,200

────────────────

Recent

−500   Lunch
−1,200 Taxi
−2,500 Shopping
+42,000 Salary
```

Don't overload V1 with financial dashboards.

## 17. Transaction History

A simple chronological feed.

```
Today

−500 ETB
Lunch
Food

−1,200 ETB
ABC Taxi
Transport

+5,000 ETB
Abebe
Income
```

Filters:

* Date
* Category
* Income/expense
* Merchant/person
* Amount

## 18. Search

This could become one of the most valuable features.

User types:

“How much did I spend on food this month?”

The app returns:

You spent 4,250 ETB on food this month.

Or:

“How much did I give Abebe?”

You sent Abebe 6,000 ETB across 3 transactions.

For V1, the underlying search should still be structured.

Don't make the AI the source of truth.

```
Natural language
       ↓
Query interpretation
       ↓
Structured transaction query
       ↓
Database
       ↓
Answer
```

## 19. Insights

Keep this simple initially.

Examples:

You spent 23% more on food this month than last month.

Your largest expense this week was Shopping — 4,200 ETB.

You spent 8,500 ETB on transportation this month.

The insights engine should operate on transactions, not directly on raw SMS.

## 20. Local-First Architecture

Given the kind of app we're building, I'd strongly recommend:

```
Flutter
   ↓
Local Database
   ↓
Sync Layer
   ↓
Backend
   ↓
Database
```

For example:

### Mobile

Flutter + Isar

### Backend

FastAPI

### Cloud

PostgreSQL would be my preference for this product.

You could still use Firebase for authentication/notifications if you want, but I would keep the actual financial transaction data in a relational database.

## 21. Sync Architecture

Don't make the app dependent on constant internet.

Example:

```
User creates transaction
        ↓
Isar
        ↓
UI updates immediately
        ↓
Outbox
        ↓
Internet available
        ↓
Backend
        ↓
PostgreSQL
```

For incoming transactions:

```
Backend
   ↓
New transaction
   ↓
Mobile sync
   ↓
Isar
   ↓
UI
```

This will also make future offline functionality much easier.

## 22. Future-Proofing for the Business Feature

This is the part I would deliberately design now.

Don't implement businesses yet.

But don't make `Transaction` permanently equal to:

```
userId → transaction
```

Instead think:

```
Owner
  ↓
Financial Account
  ↓
Transactions
```

And later:

```
Business
  ↓
Financial Account
  ↓
Transactions
  ↓
Team
```

So eventually you could have:

```
Personal Account
       ↓
Transactions

Business Account
       ↓
Transactions
       ↓
Business Team
```

The same Transaction Engine can power both.

That's the architecture I would aim for.

## 23. Future Business Extension

Not V1.

But the architecture should eventually allow:

```
Business
├── Members
├── Roles
├── Financial Accounts
├── Transactions
└── Sales
```

Then:

```
Bank SMS
    ↓
Owner's phone / Shortcut
    ↓
Transaction Engine
    ↓
Business Account
    ↓
Team
```

A salesperson could eventually see:

Payment received — 2,500 ETB

without having access to the owner's bank account.

And later:

```
Payment
   ↓
Sale
   ↓
Salesperson
   ↓
Customer
```

That's why I would not build a separate transaction architecture for the business feature.

## 24. Security

This app will handle extremely sensitive financial information.

V1 should include:

* Authentication
* Encrypted network communication
* Secure local storage for sensitive data
* Minimal raw SMS retention
* Ability to delete transactions
* Ability to delete account/data
* No sharing of transactions by default
* Explicit permissions for transaction sources

Most importantly:

Raw SMS should not become your permanent data model.

Store only the information you actually need whenever possible.

## 25. V1 Success Metric

Don't measure success by:

“How many features did we build?”

Measure:

How many transactions does the app capture automatically?

The ideal experience is:

User spends money → app knows.

If the user still has to manually enter 70% of their transactions, the product isn't solving the core problem.

## 26. V1 Development Phases

### Phase 1 — Foundation

* Authentication
* User
* Isar
* PostgreSQL
* Sync engine
* Transaction model
* Transaction repository

### Phase 2 — Manual tracking

* Add transaction
* Edit transaction
* Delete transaction
* Categories
* Transaction history

### Phase 3 — Automated ingestion

* Transaction ingestion API
* SMS parser
* Parser abstraction
* CBE parser
* Generic parser
* Duplicate detection

### Phase 4 — iPhone

* Shortcut
* Keyword filtering
* Shortcut → API
* Transaction processing

### Phase 5 — Intelligence

* Automatic categorization
* User corrections
* Merchant memory
* Review queue
* Basic insights

### Phase 6 — Polish

* Home dashboard
* Search
* Filters
* Empty states
* Error handling
* Onboarding

## 27. The V1 Architecture in One Diagram

```
                    ┌─────────────────┐
                    │   Flutter App   │
                    └────────┬────────┘
                             │
                         Isar DB
                             │
                      Sync / Outbox
                             │
                             ▼
                    ┌─────────────────┐
                    │    FastAPI      │
                    └────────┬────────┘
                             │
              ┌──────────────┴──────────────┐
              │                             │
       Transaction API                Auth / User
              │
              ▼
      ┌──────────────────┐
      │ Ingestion Engine │
      └────────┬─────────┘
               │
       ┌───────┴────────┐
       │                │
     Parser         Duplicate
       │              Check
       └───────┬────────┘
               │
         Normalization
               │
         Categorization
               │
               ▼
        ┌──────────────┐
        │ Transaction  │
        │    Engine    │
        └──────┬───────┘
               │
               ▼
          PostgreSQL
```

And the inputs:

```
                ┌── Manual Entry
                │
                ├── iPhone Shortcut
                │
                ├── Android SMS
                │
                └── Future Bank APIs
                         │
                         ▼
                  Ingestion Engine
```

### The most important design principle

Build the Transaction Engine as the foundation, not the expense-tracking UI.

Then your future products become different consumers of the same financial infrastructure:

```
                    TRANSACTION ENGINE
                           │
             ┌─────────────┼──────────────┐
             ▼             ▼              ▼
       Personal App    Business App    Future AI
             │             │              │
         Expenses       Team/Sales      Insights
```

That gives us a very clean V1 while preserving the path toward the team payment-verification feature you just described.
