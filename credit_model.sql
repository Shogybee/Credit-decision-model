------------------AVERAGE OVERDUE OVER THE MOST RCENT 6 MONTHS-------------------------------------
WITH avg_overdue AS (
			SELECT customerid,  AVG(daysOverdue) AS avg_days_overdue
			FROM paymenthistory p LEFT JOIN loanhistory l 
			ON p.loanhistoryid = l.id
			--WHERE Month >= DATEADD(MONTH, -6,  GETDATE())
			GROUP BY customerid),
-----------------------MAXIMUM TENURE, CURRENT DEBT SERICE, AVERAGE DEBT SERVICE, DEBT SERVICE RATIO AND GEARING INDEX--------------------------
gidx as(
			SELECT h.customerid, 
			MAX((DATEDIFF(DAY, disbursedDate, maturityDate) / 30)) as MT,
			SUM(loanamount / (DATEDIFF(DAY, disbursedDate, maturityDate) / 30)) as curr_debt_Service,
			AVG(loanamount / (DATEDIFF(DAY, disbursedDate, maturityDate) / 30)) as avg_debt_Service,
			(SUM(h.loanamount / (DATEDIFF(DAY, disbursedDate, maturityDate) / 30)))/ monthly_income as debt_service_ratio,
			SUM(CASE WHEN outstandingBalance > 0 THEN outstandingBalance ELSE loanAmount END) / 
			(monthly_income * (MAX((DATEDIFF(DAY, disbursedDate, maturityDate) / 30)))) AS gearing_index 
			from loanhistory h
			left join income i on h.customerid=i.customerid
			group by h.customerid, monthly_income),
-----------------------CLOSED FACILITY WITHOUT HISTORY RECORD ---------------------------------------
cf as (
			SELECT p.*,
			CASE WHEN NOT EXISTS (SELECT 1 FROM loanhistory h
								  WHERE h.[CustomerID] = p.[CustomerID]) THEN 'Closed Facility' END AS loan_status
								  FROM LoanPerformance p
								  WHERE NOT EXISTS (SELECT 1 FROM loanhistory h	WHERE h.[CustomerID] = p.[CustomerID])
								  AND PerformanceStatus = 'Performing'
								  AND OutstandingBalance = 0
								  AND Status='Closed'),
-------------------PROBABILITY OF DEFAULT ------------------------------------------------
pd as (	
			SELECT a.customerid,
			CASE WHEN avg_days_overdue > 180 THEN 0.99
				 WHEN EXISTS (SELECT 1 FROM LoanPerformance p 
							  where  p.customerid = a.customerid 
						      AND PerformanceStatus = 'Not Performing') THEN 0.99
				 WHEN avg_days_overdue > 90 THEN 0.5 + avg_days_overdue / 180
			ELSE (avg_days_overdue / 90) + (((gearing_index * MT) +  debt_service_ratio) / (MT + 1)) END AS Prob_Of_Default
			FROM avg_overdue a
			left join gidx g on a.customerid=g.customerid
			group by a.customerid, avg_days_overdue,gearing_index, debt_service_ratio,MT),
dx as (
			SELECT COALESCE(pd.CustomerID, cf.CustomerID) AS CustomerID, pd.prob_of_default,
			CASE WHEN cf.loan_status = 'Closed Facility' THEN 'CF - Approve'
				 WHEN pd.prob_of_default < 0.20 THEN 'Approve' ELSE 'Reject' END AS Decision,
			CASE WHEN cf.loan_status = 'Closed Facility' THEN '100%'
				 WHEN pd.prob_of_default IS NULL THEN '0%'
				 ELSE CONCAT(CAST(ROUND(100 * (1 - prob_of_default), 2) AS DECIMAL(5,2)), '%') END AS Score
			FROM pd
			FULL   JOIN cf ON pd.CustomerID = cf.CustomerID)

select dx.*, (0.333 * monthly_income) as serviceable_loan_amount,
CASE WHEN prob_of_default IS NULL AND decision='Reject' THEN 'No Disbursed Date Reported'
	 WHEN prob_of_default IS NULL AND decision='CF - Approve' THEN 'Closed with Performing Loans'
	 WHEN prob_of_default < 0.20 THEN 'Low Risk'
	 WHEN prob_of_default >= 0.20 AND prob_of_default < 0.40 THEN 'Moderate Risk'
	 WHEN prob_of_default >= 0.40 AND prob_of_default < 0.60 THEN 'High Risk'
	 WHEN prob_of_default >= 0.6 THEN 'Very High Risk'
END AS Risk_Category
from dx 
left join income i on dx.customerid=i.customerid








 
