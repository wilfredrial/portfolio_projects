-- I want to look at population changes across the United States
-- since 2020. The US Census websites provided a file showing 
-- a base number on April 1, 2020 and estimates on July 1 in 2020, 
-- 2021, and 2022 I am most interested in the difference between 
-- April 1, 2020 and July 1, 2022. 


-- Let's create the table so we can load the data to a table
create table us_counties (
	geo_area varchar(75),
	base_2020 integer,
	estimate_2020 integer,
	estimate_2021 integer,
	estimate_2022 integer
);
	
	
-- Copy data from csv file to table
copy us_counties --(geo_area, base_2020, estimate_2020, estimate_2021, estimate_2022)
from '/path/to/us_county_pop_20-22.csv' 
with (format csv, header);


-- Inspect the first 5 rows of the table
select * 
from us_counties
limit 5;
-- Here are the first 5 rows without headers:
	-- "United States"	331449520	331511512	332031554	333287557
	-- ".Autauga County, Alabama"	58802	58902	59210	59759
	-- ".Baldwin County, Alabama"	231761	233219	239361	246435
	-- ".Barbour County, Alabama"	25224	24960	24539	24706
	-- ".Bibb County, Alabama"	22300	22183	22370	22005
-- I want to delete the first row and separate the first column into 
-- two new columns for the county and state 


-- Let's create a backup copy before we make any changes 
-- we may regret
CREATE TABLE us_counties_backup AS
SELECT * FROM us_counties;


-- count all rows in both tables to double check
SELECT
    (SELECT count(*) FROM us_counties) AS original,
    (SELECT count(*) FROM us_counties_backup) AS backup;
-- 3145 rows each. Success!
	
	
-- delete first row with country data
DELETE FROM us_counties_backup
WHERE geo_area = 'United States';


-- Add new columns for county and state
ALTER TABLE us_counties_backup
ADD COLUMN county VARCHAR(50),
ADD COLUMN state_name VARCHAR(25);


-- Update the new columns with county and state information
UPDATE us_counties_backup
SET
    county = substring(geo_area, '^\.([^,]+),\s([A-Za-z\s]+)$'), -- regex to get county name; also removes initial '.'
    state_name = split_part(geo_area, ', ', 2); -- split around the ', ' and retrieves the state name
	
-- Inspect the new rows
select * 
from 
	us_counties_backup 
limit 5;
-- The table looks good now!
-- Now that our data is cleaned up, let's start investigating the data


-- State populations in 2020 and 2022
select 
	state_name,
	sum(us_bk.base_2020) as state_pop_2020,
	sum(us_bk.estimate_2022) as state_pop_2022
from us_counties_backup us_bk
group by state_name
order by state_pop_2020 desc;
-- Top 5 states:
-- "state_name"
-- "California"
-- "Texas"
-- "Florida"
-- "New York"
-- "Pennsylvania"


-- County population by greatest percent increase
select 
	county,
	state_name,
	us_bk.base_2020,
	us_bk.estimate_2022,
	round( 
			(CAST(us_bk.estimate_2022 AS numeric(8,1)) - us_bk.base_2020) 
			/ us_bk.base_2020 * 100, 
			3
	) AS pct_change_2020_2022
from us_counties_backup us_bk
order by pct_change_2020_2022 desc;
-- Too many small population counties with fewer than 10k residents...


-- County population greatest percent gains, with 100k or more
select 
	county,
	state_name,
	us_bk.base_2020,
	us_bk.estimate_2022,
	(us_bk.estimate_2022 - us_bk.base_2020) as pop_diff,
	round( 
			(CAST(us_bk.estimate_2022 AS numeric(8,1)) - us_bk.base_2020) 
			/ us_bk.base_2020 * 100, 
			3
	) AS pct_change_2020_2022
from us_counties_backup us_bk
where 
	(us_bk.base_2020 >= 100000) 
	or
	(us_bk.estimate_2022 >= 100000)
order by pct_change_2020_2022 desc;
-- Texas counties occupied 7 of the 10 top percent gains
-- Kaufman county increased by 18.6%
-- A quick google search reveals Kaufman county borders Dallas


-- greatest percent losers with at least 100k residents
select 
	county,
	state_name,
	us_bk.base_2020,
	us_bk.estimate_2022,
	(us_bk.estimate_2022 - us_bk.base_2020) as pop_diff,
	round( 
			(CAST(us_bk.estimate_2022 AS numeric(8,1)) - us_bk.base_2020) 
			/ us_bk.base_2020 * 100, 
			3
	) AS pct_change_2020_2022
from us_counties_backup us_bk
where 
	(us_bk.base_2020 >= 100000) 
	or
	(us_bk.estimate_2022 >= 100000)
order by pct_change_2020_2022 asc;
-- San Francisco County tops the list with 7.5% decrease
-- Four New York counties appeared in the top 10


-- Which counties saw the greatest population increase?
select 
	county,
	state_name,
	us_bk.base_2020,
	us_bk.estimate_2022,
	(us_bk.estimate_2022 - us_bk.base_2020) as pop_diff,
	round( 
			(CAST(us_bk.estimate_2022 AS numeric(8,1)) - us_bk.base_2020) 
			/ us_bk.base_2020 * 100, 
			3
	) AS pct_change_2020_2022
from us_counties_backup us_bk
order by pop_diff desc;
-- Arizona's Maricopa County grew the most with +130k 
-- Counties in Texas appear 5 times in the top 10


-- Which counties saw the greatest population decrease?
select 
	county,
	state_name,
	us_bk.base_2020,
	us_bk.estimate_2022,
	(us_bk.estimate_2022 - us_bk.base_2020) as pop_diff,
	round( (CAST(us_bk.estimate_2022 AS numeric(8,1)) - us_bk.base_2020) / us_bk.base_2020 * 100, 3 ) AS pct_change_2020_2022
from us_counties_backup us_bk
order by pop_diff asc;
-- Los Angeles County lost the most at nearly -300k
-- New York and California counties appear 4 times each in the top 10

-- There appears to be a trend of loss in both New York and California
-- mirrored by a gain in Texas. Let's look at the population changes at the state level


-- State population gains
with 
	state_pop (state_name, base_2020, estimate_2022)
as
	(
		select
			state_name,
			sum(base_2020),
			sum(estimate_2022)
		from 
			us_counties_backup
		group by state_name
	)
select 
	state_name, 
	base_2020,
	estimate_2022,
	estimate_2022 - base_2020 as pop_diff,
	round( (CAST(estimate_2022 AS numeric(9,1)) - base_2020) / base_2020 * 100, 3 ) AS pct_change
from 
	state_pop
order by pop_diff desc
-- Texas tops the list with an increase of 884k
-- Florida, North Carolina, Arizona, Georgia, South Carolina follow
-- Many of these are in the south eastern area of the US


-- State population losses
with 
	state_pop (state_name, base_2020, estimate_2022)
as
	(
		select
			state_name,
			sum(base_2020),
			sum(estimate_2022)
		from 
			us_counties_backup
		group by state_name
	)
select 
	state_name, 
	base_2020,
	estimate_2022,
	estimate_2022 - base_2020 as pop_diff,
	round( (CAST(estimate_2022 AS numeric(9,1)) - base_2020) / base_2020 * 100, 3 ) AS pct_change
from 
	state_pop
order by pop_diff asc
-- New York and California were placed 1st and 2nd in the list of greatest losses
-- Illinois is the only other state with more than 100k losses


-- Since many of the top gains appear to be southern states,
-- I would like to see how population trends appear on regional level
-- The US Census divides the US into four regions: Northeast,
-- South, Midwest, and West

-- Let's add another table with the region data
create table us_regions (
	state_name varchar(30),
	state_code varchar(2),
	region varchar(10),
	division varchar(20)
)

-- copy data from csv file to table
copy us_regions 
from '/path/to/your/csv/file.csv' 
with (format csv, header);


-- Regional population differences
with 
	region_pop (us_region, base_2020, estimate_2022)
as
	(
		select
			us_regions.region,
			sum(usbk.base_2020),
			sum(usbk.estimate_2022)
		from 
			us_counties_backup usbk join us_regions on usbk.state_name = us_regions.state_name
		group by us_regions.region
	)
select 
	us_region, 
	base_2020,
	estimate_2022,
	estimate_2022 - base_2020 as pop_diff,
	round( (CAST(estimate_2022 AS numeric(10,1)) - base_2020) / base_2020 * 100, 3 ) AS pct_change
from 
	region_pop
order by pop_diff desc
-- The results show the Northeast region lost the most (-568k) and 
-- the South gained the most (+2.4 million)
-- The West received marginal increases (+154k)

-- With only 4 regions, it is difficult to come to many conclusions
-- The census further breaks up each region into 2 or 3 divisions
-- for a total of 9 divisions. Let's aggregate by division for 
-- greater granularity

-- Census division population changes
with 
	division_pop (us_division, us_region, base_2020, estimate_2022)
as
	(
		select
			us_regions.division,
			us_regions.region,
			sum(usbk.base_2020),
			sum(usbk.estimate_2022)
		from 
			us_counties_backup usbk join us_regions on usbk.state_name = us_regions.state_name
		group by 	
			us_regions.division, 
			us_regions.region
	)
select 
	us_division, 
	us_region,
	base_2020,
	estimate_2022,
	estimate_2022 - base_2020 as pop_diff,
	round( (CAST(estimate_2022 AS numeric(10,1)) - base_2020) / base_2020 * 100, 3 ) AS pct_change
from 
	division_pop
order by pop_diff desc
-- This query explains a lot more. All divisions in the South saw population increases,
-- especially the South Atlantic division
-- The greatest losses occur in the Pacific and Middle Atlantic divisions, which hold
-- California and New York, respectively.
