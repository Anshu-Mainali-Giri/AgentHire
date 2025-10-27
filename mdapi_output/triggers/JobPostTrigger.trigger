trigger JobPostTrigger on Job_Post__c (before insert) {
    JobPostHandler.setStatusNew(Trigger.new);
}