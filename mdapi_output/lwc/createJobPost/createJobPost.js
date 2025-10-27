// createJobPost.js
import { LightningElement, api, wire, track } from 'lwc';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import { NavigationMixin, CurrentPageReference } from 'lightning/navigation';
import { getRecordIdFromPageRef } from 'c/inContextUtils';

export default class CreateJobPost extends NavigationMixin(LightningElement) {
    @api recordId;  
    @track isEdit = false;

    @wire(CurrentPageReference)
    setCurrentPageReference(pageRef) {
        // Use utility function
        this.recordId = this.recordId || getRecordIdFromPageRef(pageRef);
        this.isEdit = !!this.recordId;
    }

    // Dynamic title
    get pageTitle() {
        return this.isEdit ? 'Edit Job Post' : 'New Job Post';
    }

    // Dynamic button text
    get buttonLabel() {
        return this.isEdit ? 'Update' : 'Post';
    }

    // Success handler
    handleSuccess(event) {
        const newRecordId = event.detail.id;
        this.dispatchEvent(
            new ShowToastEvent({
                title: 'Success',
                message: this.isEdit
                    ? 'Job Post updated successfully!'
                    : 'Job Post created successfully!',
                variant: 'success'
            })
        );

        this[NavigationMixin.Navigate]({
            type: 'standard__recordPage',
            attributes: {
                recordId: newRecordId,
                objectApiName: 'Job_Post__c',
                actionName: 'view'
            }
        });
    }

    // Cancel or Close handler
    handleClose() {
        if (this.isEdit) {
            this[NavigationMixin.Navigate]({
                type: 'standard__recordPage',
                attributes: {
                    recordId: this.recordId,
                    objectApiName: 'Job_Post__c',
                    actionName: 'view'
                }
            });
        } else {
            this[NavigationMixin.Navigate]({
                type: 'standard__objectPage',
                attributes: {
                    objectApiName: 'Job_Post__c',
                    actionName: 'list'
                }
            });
        }
    }
}
