@isTest
public class JobPostTestFactory {

    // Create a single Job Post record
    public static Job_Post__c createJobPost(Boolean doInsert) {
        Job_Post__c job = new Job_Post__c(
            Job_Title__c = 'React Developer',
            Job_Description__c = 'React Developer',
            Required_Skills__c = 'React, JavaScript, HTML, CSS',
            Location__c = 'Remote (WFH)',
            Experience_Required__c = 3
        );

        if (doInsert) {
            insert job;
        }
        return job;
    }

}
