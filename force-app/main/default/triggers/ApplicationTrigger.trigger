trigger ApplicationTrigger on Candidate__c (after insert) {
    List<Application__c> appsToCreate = new List<Application__c>();
    
    Set<Id> jobPostIds = new Set<Id>();
    for(Candidate__c candidate: Trigger.new){
        if (candidate.Job_Post__c != null){
            jobPostIds.add(candidate.Job_Post__c);
        }
    }
    
    Map<Id, Job_Post__c> jobPostMap = new Map<Id, Job_Post__c>([
        SELECT Id, Job_Title__c FROM Job_Post__c WHERE Id IN :jobPostIds
    ]);

    for(Candidate__c candidate: Trigger.new){
        if (candidate.Job_Post__c != null){
            Job_Post__c jobPost = jobPostMap.get(candidate.Job_Post__c);
            String jobTitle = jobPost != null ? jobPost.Job_Title__c : 'Unknown Job';
            
            Application__c app = new Application__c(
                Name = candidate.Candidate_Name__c + ' - ' + jobTitle,
                Candidate__c = candidate.Id,
                Job_Post__c = candidate.Job_Post__c,
                Application_Date__c = System.today(),
                Application_Status__c = 'New'
            );
            appsToCreate.add(app);
        }
    }
    if (!appsToCreate.isEmpty()){
        insert appsToCreate;
    }
}
