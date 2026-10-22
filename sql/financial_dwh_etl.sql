/* ==========================================================================
   Financial Transactions Data Warehouse  -  full ETL script (SQL Server)
   Source: Kaggle "Financial Transactions Dataset: Analytics" (computingvictor)
   Put the CSV files in C:\data before running the BULK INSERT steps.
   Run the sections in order.
   ========================================================================== */

-- 1) Database ---------------------------------------------------------------
CREATE DATABASE FinancialDWH;
GO
USE FinancialDWH;
GO

-- 2) Staging tables (raw text, cleaned later) ---------------------------------
CREATE TABLE stg_cards (
    id INT, client_id INT, card_brand VARCHAR(50), card_type VARCHAR(50),
    card_number VARCHAR(30), expires VARCHAR(10), cvv VARCHAR(10),
    has_chip VARCHAR(5), num_cards_issued INT, credit_limit VARCHAR(20),
    acct_open_date VARCHAR(10), year_pin_last_changed INT, card_on_dark_web VARCHAR(5)
);
CREATE TABLE stg_users (
    id INT, current_age INT, retirement_age INT, birth_year INT, birth_month INT,
    gender VARCHAR(10), address VARCHAR(200), latitude DECIMAL(9,4), longitude DECIMAL(9,4),
    per_capita_income VARCHAR(30), yearly_income VARCHAR(30), total_debt VARCHAR(30),
    credit_score INT, num_credit_cards INT
);
CREATE TABLE stg_transactions (
    id BIGINT, [date] VARCHAR(25), client_id INT, card_id INT, amount VARCHAR(20),
    use_chip VARCHAR(30), merchant_id INT, merchant_city VARCHAR(100),
    merchant_state VARCHAR(50), zip VARCHAR(20), mcc INT, errors VARCHAR(200)
);
GO

-- 3) Load the CSV files ---------------------------------------------------------
BULK INSERT stg_cards FROM 'C:\data\cards_data.csv'
WITH (FORMAT = 'CSV', FIRSTROW = 2, FIELDTERMINATOR = ',', ROWTERMINATOR = '0x0d0a', TABLOCK);

BULK INSERT stg_users FROM 'C:\data\users_data.csv'
WITH (FIRSTROW = 2, FIELDTERMINATOR = ',', ROWTERMINATOR = '0x0a', TABLOCK);

BULK INSERT stg_transactions FROM 'C:\data\transactions_data.csv'
WITH (FORMAT = 'CSV', FIELDQUOTE = '"', FIRSTROW = 2, FIELDTERMINATOR = ',',
      ROWTERMINATOR = '0x0a', BATCHSIZE = 500000, TABLOCK);
GO
-- Expected: 6,146 cards | 2,000 users | 13,305,915 transactions

-- 4) Dim_Card  (card number masked to last 4 digits; cvv / dark-web flag dropped) ---
CREATE TABLE Dim_Card (
    card_key INT PRIMARY KEY, client_id INT, card_brand VARCHAR(50), card_type VARCHAR(50),
    card_last4 CHAR(4), expiry_date DATE, has_chip BIT, num_cards_issued INT,
    credit_limit DECIMAL(12,2), acct_open_date DATE, year_pin_last_changed INT
);
GO
INSERT INTO Dim_Card
SELECT id, client_id, card_brand, card_type, RIGHT(card_number, 4),
       DATEFROMPARTS(CAST(RIGHT(expires, 4) AS INT), CAST(LEFT(expires, 2) AS INT), 1),
       CASE WHEN has_chip = 'YES' THEN 1 ELSE 0 END,
       num_cards_issued,
       CAST(REPLACE(REPLACE(credit_limit, '$', ''), ',', '') AS DECIMAL(12,2)),
       DATEFROMPARTS(CAST(RIGHT(acct_open_date, 4) AS INT), CAST(LEFT(acct_open_date, 2) AS INT), 1),
       year_pin_last_changed
FROM stg_cards;
GO

-- 5) Dim_Client  (address dropped: personal data, not needed for analysis) ---------
CREATE TABLE Dim_Client (
    client_key INT PRIMARY KEY, current_age INT, retirement_age INT, birth_year INT, birth_month INT,
    gender VARCHAR(10), latitude DECIMAL(9,4), longitude DECIMAL(9,4),
    per_capita_income DECIMAL(12,2), yearly_income DECIMAL(12,2), total_debt DECIMAL(12,2),
    credit_score INT, num_credit_cards INT
);
GO
INSERT INTO Dim_Client
SELECT id, current_age, retirement_age, birth_year, birth_month, gender, latitude, longitude,
       CAST(REPLACE(REPLACE(LTRIM(RTRIM(per_capita_income)), '$', ''), ',', '') AS DECIMAL(12,2)),
       CAST(REPLACE(REPLACE(LTRIM(RTRIM(yearly_income)),     '$', ''), ',', '') AS DECIMAL(12,2)),
       CAST(REPLACE(REPLACE(LTRIM(RTRIM(total_debt)),        '$', ''), ',', '') AS DECIMAL(12,2)),
       credit_score, num_credit_cards
FROM stg_users;
GO

-- 6) Dim_Merchant -------------------------------------------------------------------
CREATE TABLE Dim_Merchant (
    merchant_key INT PRIMARY KEY, merchant_city VARCHAR(100), merchant_state VARCHAR(50), zip CHAR(5)
);
GO
INSERT INTO Dim_Merchant
SELECT merchant_id, MAX(merchant_city), MAX(merchant_state),
       MAX(CASE WHEN zip IS NULL OR LTRIM(RTRIM(zip)) = '' THEN NULL
                ELSE RIGHT('00000' + LEFT(zip, CHARINDEX('.', zip + '.') - 1), 5) END)
FROM stg_transactions
GROUP BY merchant_id;
GO

-- 7) Dim_MCC  (from mcc_codes.json) ------------------------------------------------------
CREATE TABLE Dim_MCC (mcc_key INT PRIMARY KEY, mcc_description VARCHAR(200));
GO
DECLARE @json NVARCHAR(MAX) = N'{
"5812":"Eating Places and Restaurants","5541":"Service Stations","7996":"Amusement Parks, Carnivals, Circuses",
"5411":"Grocery Stores, Supermarkets","4784":"Tolls and Bridge Fees","4900":"Utilities - Electric, Gas, Water, Sanitary",
"5942":"Book Stores","5814":"Fast Food Restaurants","4829":"Money Transfer","5311":"Department Stores",
"5211":"Lumber and Building Materials","5310":"Discount Stores","3780":"Computer Network Services",
"5499":"Miscellaneous Food Stores","4121":"Taxicabs and Limousines","5300":"Wholesale Clubs",
"5719":"Miscellaneous Home Furnishing Stores","7832":"Motion Picture Theaters","5813":"Drinking Places (Alcoholic Beverages)",
"4814":"Telecommunication Services","5661":"Shoe Stores","5977":"Cosmetic Stores","8099":"Medical Services",
"7538":"Automotive Service Shops","5912":"Drug Stores and Pharmacies","4111":"Local and Suburban Commuter Transportation",
"5815":"Digital Goods - Media, Books, Apps","8021":"Dentists and Orthodontists","5921":"Package Stores, Beer, Wine, Liquor",
"5655":"Sports Apparel, Riding Apparel Stores","7230":"Beauty and Barber Shops","3390":"Miscellaneous Metalwork",
"7922":"Theatrical Producers","3722":"Passenger Railways","5651":"Family Clothing Stores",
"4899":"Cable, Satellite, and Other Pay Television Services","5251":"Hardware Stores",
"7995":"Betting (including Lottery Tickets, Casinos)","3596":"Miscellaneous Machinery and Parts Manufacturing",
"3730":"Ship Chandlers","9402":"Postal Services - Government Only","7801":"Athletic Fields, Commercial Sports",
"5970":"Artist Supply Stores, Craft Shops","5932":"Antique Shops","5621":"Women''s Ready-To-Wear Stores",
"7349":"Cleaning and Maintenance Services","4722":"Travel Agencies","5193":"Florists Supplies, Nursery Stock and Flowers",
"3775":"Railroad Freight","3684":"Semiconductors and Related Devices","5045":"Computers, Computer Peripheral Equipment",
"3504":"Gardening Supplies","7011":"Lodging - Hotels, Motels, Resorts","8041":"Chiropractors",
"4214":"Motor Freight Carriers and Trucking","6300":"Insurance Sales, Underwriting","8011":"Doctors, Physicians",
"3509":"Industrial Equipment and Supplies","7210":"Laundry Services","5192":"Books, Periodicals, Newspapers",
"7542":"Car Washes","3640":"Lighting, Fixtures, Electrical Supplies","7393":"Detective Agencies, Security Services",
"8111":"Legal Services and Attorneys","3771":"Railroad Passenger Transport","5732":"Electronics Stores",
"5094":"Precious Stones and Metals","5712":"Furniture, Home Furnishings, and Equipment Stores","5816":"Digital Goods - Games",
"7802":"Recreational Sports, Clubs","3389":"Non-Precious Metal Services","8043":"Optometrists, Optical Goods and Eyeglasses",
"3393":"Heat Treating Metal Services","3174":"Upholstery and Drapery Stores","3001":"Steel Products Manufacturing",
"3395":"Welding Repair","3058":"Tools, Parts, Supplies Manufacturing","8049":"Podiatrists",
"3387":"Electroplating, Plating, Polishing Services","4112":"Passenger Railways","3405":"Ironwork",
"5261":"Lawn and Garden Supply Stores","3144":"Floor Covering Stores","3132":"Leather Goods","3359":"Non-Ferrous Metal Foundries",
"8931":"Accounting, Auditing, and Bookkeeping Services","8062":"Hospitals","7276":"Tax Preparation Services","4131":"Bus Lines",
"3260":"Pottery and Ceramics","3256":"Brick, Stone, and Related Materials","3006":"Miscellaneous Fabricated Metal Products",
"7531":"Automotive Body Repair Shops","1711":"Heating, Plumbing, Air Conditioning Contractors","5947":"Gift, Card, Novelty Stores",
"3007":"Coated and Laminated Products","4511":"Airlines","3075":"Bolt, Nut, Screw, Rivet Manufacturing",
"3066":"Miscellaneous Metals","3005":"Miscellaneous Metal Fabrication","4411":"Cruise Lines","3000":"Steelworks",
"5533":"Automotive Parts and Accessories Stores","3008":"Steel Drums and Barrels","7549":"Towing Services",
"5941":"Sporting Goods Stores","5722":"Household Appliance Stores","3009":"Fabricated Structural Metal Products",
"5733":"Music Stores - Musical Instruments"}';
INSERT INTO Dim_MCC SELECT CAST([key] AS INT), [value] FROM OPENJSON(@json);
GO

-- 8) Dim_Date (2010-2019) -----------------------------------------------------------------
CREATE TABLE Dim_Date (
    date_key INT PRIMARY KEY, full_date DATE, [year] INT, [quarter] INT, [month] INT,
    month_name VARCHAR(20), [day] INT, day_of_week INT, day_name VARCHAR(20), is_weekend BIT
);
GO
DECLARE @start DATE = '2010-01-01', @end DATE = '2019-12-31';
WITH dates AS (
    SELECT @start AS d UNION ALL SELECT DATEADD(DAY, 1, d) FROM dates WHERE d < @end
)
INSERT INTO Dim_Date
SELECT YEAR(d) * 10000 + MONTH(d) * 100 + DAY(d), d, YEAR(d), DATEPART(QUARTER, d), MONTH(d),
       DATENAME(MONTH, d), DAY(d), DATEPART(WEEKDAY, d), DATENAME(WEEKDAY, d),
       CASE WHEN DATENAME(WEEKDAY, d) IN ('Saturday', 'Sunday') THEN 1 ELSE 0 END
FROM dates OPTION (MAXRECURSION 0);
GO

-- 9) Fact_Transactions ------------------------------------------------------------------------
ALTER DATABASE FinancialDWH SET RECOVERY SIMPLE;
GO
CREATE TABLE Fact_Transactions (
    transaction_id BIGINT PRIMARY KEY, date_key INT, transaction_time TIME(0),
    client_key INT, card_key INT, merchant_key INT, mcc_key INT,
    amount DECIMAL(12,2), use_chip VARCHAR(30), errors VARCHAR(200)
);
GO
INSERT INTO Fact_Transactions WITH (TABLOCK)
SELECT id,
       CAST(CONVERT(CHAR(8), CAST([date] AS DATE), 112) AS INT),
       CAST(CAST([date] AS DATETIME2(0)) AS TIME(0)),
       client_id, card_id, merchant_id, mcc,
       CAST(REPLACE(REPLACE(LTRIM(RTRIM(amount)), '$', ''), ',', '') AS DECIMAL(12,2)),
       use_chip, errors
FROM stg_transactions
ORDER BY id;
GO

-- 10) Foreign keys (star schema) -------------------------------------------------------------------
ALTER TABLE Fact_Transactions ADD CONSTRAINT FK_Fact_Date     FOREIGN KEY (date_key)     REFERENCES Dim_Date(date_key);
ALTER TABLE Fact_Transactions ADD CONSTRAINT FK_Fact_Client   FOREIGN KEY (client_key)   REFERENCES Dim_Client(client_key);
ALTER TABLE Fact_Transactions ADD CONSTRAINT FK_Fact_Card     FOREIGN KEY (card_key)     REFERENCES Dim_Card(card_key);
ALTER TABLE Fact_Transactions ADD CONSTRAINT FK_Fact_Merchant FOREIGN KEY (merchant_key) REFERENCES Dim_Merchant(merchant_key);
ALTER TABLE Fact_Transactions ADD CONSTRAINT FK_Fact_MCC      FOREIGN KEY (mcc_key)      REFERENCES Dim_MCC(mcc_key);
GO

-- 11) Sanity checks ---------------------------------------------------------------------------------
SELECT COUNT(*) AS total_transactions, SUM(amount) AS total_amount, AVG(amount) AS avg_amount,
       SUM(CASE WHEN amount < 0 THEN 1 ELSE 0 END) AS refund_transactions,
       COUNT(DISTINCT merchant_key) AS active_merchants,
       CAST(100.0 * SUM(CASE WHEN use_chip = 'Online Transaction' THEN 1 ELSE 0 END) / COUNT(*) AS DECIMAL(5,2)) AS online_pct
FROM Fact_Transactions;
-- Expected: 13,305,915 | 571,835,522.28 | 42.98 | 660,049 | 74,831 | 11.71
