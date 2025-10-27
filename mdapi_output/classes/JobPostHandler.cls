public with sharing class JobPostHandler {

    //When Job Post is saved, Satus is set to New
    public static void setStatusNew(List<Job_Post__c> records) {
        for (Job_Post__c rec : records) {
            rec.Status__c = 'Open';
        }
    }
}