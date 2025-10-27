@isTest
private class JobPostHandlerTest {

    @isTest
    static void testSetStatusNew() {
        // Use factory to create & insert a record
        Job_Post__c job = JobPostTestFactory.createJobPost(true);

        // Query back the record
        Job_Post__c insertedJob = [
            SELECT Id, Job_Title__c, Status__c
            FROM Job_Post__c
            WHERE Id = :job.Id
        ];

        // Verify the trigger/handler sets the Status to 'Open'
        System.assertEquals('Open', insertedJob.Status__c,
            'Status should be automatically set to Open after insert');
    }
}
