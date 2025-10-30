trigger ApplicationTrigger on SOBJECT (after insert) {
    List <Application__c> appsToCreate = new <Application__c>();

    for(Candidate__c candidate: Trigger.new){
        if (candidate.Job_Post__c !=null){
            Application__c app = new Application__c(
                Name = candidate.Name + 'Application',
                Candidate__c = candidate.Id,
                Job_Post__c = candidate.Job_Post__c,
                Application_Date__c = System.today()
            );
            appsToCreate.add(app);
        }
    }
    if (!appsToCreate.isEmpty()){
        insert appsToCreate;
    }

}