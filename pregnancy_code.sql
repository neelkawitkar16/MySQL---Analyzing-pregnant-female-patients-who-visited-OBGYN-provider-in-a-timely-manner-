-- female patients with age greater than 17
drop table kp_patient_encounter;

create table kp_patient_encounter as
select a.unique_patient_id, a.gender, a.birth_date
	, b.enc_id, b.visit_prov_id, b.enc_status, b.enc_date, b.due_date
    , TIMESTAMPDIFF(YEAR, a.birth_date, b.enc_date) as age
from patient_table a
left join encounter_table b
	on a.unique_patient_id = b.enc_patient_id
where gender = 'F' and TIMESTAMPDIFF(YEAR, a.birth_date, b.enc_date) > 17
order by a.unique_patient_id, b.enc_date
;
 
-- visiting provider specialty = OBGYN 
drop table kp_pat_prov_enc;

create table kp_pat_prov_enc as 
select a.*, b.prov_name, b.prov_spec
from kp_patient_encounter as a
left join provider_table as b
	on a.visit_prov_id = b.prov_id 
where upper(prov_spec) = 'OBGYN'
order by a.unique_patient_id, a.enc_date
;

-- encounters with preganancy codes 
drop table kp_preg_enc;

create table kp_preg_enc as 
select distinct a.dx_enc_id, b.codes as preg_code
from encounter_dx_table as a
left join pregnancy_diagnosis as b
	on a.dx_icd = b.codes
where b.codes is not null
order by a.dx_enc_id
;

-- encounters with either due date populated or pregnancy diagnosis 
drop table kp_preg_pat_prov_enc;
 
create table kp_preg_pat_prov_enc as 
select a.*, b.preg_code 
from kp_pat_prov_enc as a 
left join kp_preg_enc as b
	on a.enc_id = b.dx_enc_id
where (a.due_date <> '0000-00-00' and a.due_date > a.enc_date)
	or b.preg_code is not null
;

-- identify multiple encounters
drop table denominator;

create table denominator as 
select a.*, TIMESTAMPDIFF(WEEK, a.enc_date, a.due_date) as weeks_due
	, rank() over (partition by a.unique_patient_id order by a.enc_date, a.enc_id) as seq
from kp_preg_pat_prov_enc a 
order by a.unique_patient_id, a.enc_date
;

-- get only 1st encounter from multiple encounters
drop table final_denominator;

create table final_denominator as 
select unique_patient_id, gender, age, 
	visit_prov_id, prov_spec, 
	enc_id, enc_status, enc_date, due_date, weeks_due, preg_code, 1 as denominator
from denominator  
where seq = 1
;

-- denominator count
select count(unique_patient_id)
from final_denominator 
;


/*Numerator calculation begins*/

-- The number of patients with a completed visit to the OBGYN between 40 and 27 weeks prior to delivery.

drop table kp_numerator_1;

create table kp_numerator_1 as 
select a.*
	, case when (a.enc_status = 'Completed' or a.enc_status = 'Compeleted') and a.weeks_due>=27 and a.weeks_due<=40 then 1 else 0 end as due_date_numerator
from denominator a
order by a.unique_patient_id, a.enc_id, a.visit_prov_id
;

-- Pregnant member identified solely by diagnoses should have an encounter within 6 weeks of diagnosis 
drop table kp_numerator_2;

create table kp_numerator_2 as 
select a.*
	, b.enc_date as next_enc_date
	, TIMESTAMPDIFF(WEEK, b.enc_date, a.enc_date) as preg_follow_up_weeks
	, case when b.preg_code is not null and TIMESTAMPDIFF(WEEK, b.enc_date, a.enc_date) <= 6 then 1 else 0 end as preg_follow_up_numerator
from denominator a
left join denominator b
	on a.unique_patient_id = b.unique_patient_id
		and b.seq = a.seq - 1
order by a.unique_patient_id, a.enc_date
;


-- combining to get numerator
drop table final_numerator;

create table final_numerator as
select a.unique_patient_id, a.gender, a.age, a.visit_prov_id, a.prov_spec
	, a.enc_id, a.enc_status, a.enc_date, a.due_date, a.weeks_due, a.due_date_numerator
	, a.preg_code, b.preg_follow_up_weeks, b.preg_follow_up_numerator, case when a.due_date_numerator = 1 or b.preg_follow_up_numerator = 1 then 1 else 0 end as numerator 
from kp_numerator_1 a 
left join kp_numerator_2 b
	on a.unique_patient_id = b.unique_patient_id
		and a.enc_id = b.enc_id
where a.seq = 1
order by a.unique_patient_id, a.enc_date
;


/**********************************************/
-- final table with denom and num 
drop table kp_preganancy_case_study;

create table kp_preganancy_case_study as
select a.*, b.numerator
from final_denominator a
left join final_numerator b
	on a.unique_patient_id = b.unique_patient_id
		and a.enc_id = b.enc_id
;

select *
from kp_preganancy_case_study
;

-- Percentage
drop table preg_percentage;

create table preg_percentage as
select sum(numerator) as num, sum(denominator) as denom, round((sum(numerator)/sum(denominator))*100,2) as rate
from kp_preganancy_case_study
;

select *
from preg_percentage
;


