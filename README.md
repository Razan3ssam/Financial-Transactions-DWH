# Financial Transactions Data Warehouse & Power BI Dashboard

An end-to-end analytics project: raw card-transaction data -> cleaned **star-schema data warehouse in SQL Server** -> interactive **Power BI dashboard** (soft yellow & olive theme).

## Dataset
[Financial Transactions Dataset: Analytics](https://www.kaggle.com/datasets/computingvictor/transactions-fraud-datasets) (Kaggle).
The raw files (~1.4 GB) are **not included** in this repo. Download them from Kaggle and place them in `C:\data`.

| File | Used for |
|---|---|
| `transactions_data.csv` (13.3M rows) | `Fact_Transactions` |
| `users_data.csv` (2,000 clients) | `Dim_Client` |
| `cards_data.csv` (6,146 cards) | `Dim_Card` |
| `mcc_codes.json` (109 codes) | `Dim_MCC` |

## Star schema
`Fact_Transactions` surrounded by `Dim_Date`, `Dim_Client`, `Dim_Card`, `Dim_Merchant`, `Dim_MCC`.
See `images/star_schema.png`.

## ETL highlights (SQL Server)
- Bulk-loaded 13.3M rows into staging tables, then cleaned into typed dimension/fact tables.
- Converted `$`-formatted text to `DECIMAL`, `MM/YYYY` text to `DATE`, zip codes like `58523.0` to 5-digit text.
- Privacy: card numbers masked to the last 4 digits; CVV, client address and a constant `card_on_dark_web` flag dropped.
- Foreign keys added and verified (0 orphan rows); totals reconciled between SQL and Power BI.

Full script: [`sql/financial_dwh_etl.sql`](sql/financial_dwh_etl.sql)

## Dashboard pages
1. **Home** - navigation hub with headline numbers
2. **Transactions Overview** - volume and amount over time, by weekday, by transaction type
3. **Cards & Clients** - brands, card types, credit limits, client profile
4. **Merchants & Categories** - top categories (MCC), states and cities

Screenshots: `images/` | PDF export: `dashboard/Financial_Dashboard.pdf`

## Tools
SQL Server 2025, SSMS 22, Power BI Desktop, DAX.

## Key numbers
13.3M transactions | $571.8M net amount | 6,146 cards | 2,000 clients | 74,831 merchants | 109 categories

## Author
Razan Essam
