import { LightningElement } from 'lwc';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import { NavigationMixin } from 'lightning/navigation';

export default class CreateJobPost extends NavigationMixin(LightningElement) {
    handleSuccess(event) {
        const recordId = event.detail.id;

        // Show Sucess message when new job is created
        this.dispatchEvent(
            new ShowToastEvent({
                title: 'Success',
                message: 'Job Post created successfully!',
                variant: 'success'
            })
        );

        // Redirect to the new record page when Post button is clicked
        this[NavigationMixin.Navigate]({
            type: 'standard__recordPage',
            attributes: {
                recordId: recordId,
                objectApiName: 'Job_Post__c',
                actionName: 'view'
            }
        });
    }
}