import { LightningElement, api, wire } from 'lwc';
import { getRecord } from 'lightning/uiRecordApi';
import fetchCandidates from '@salesforce/apex/CandidateAPIService.fetchCandidates';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';

// Only fields needed for context
import JOB_TITLE from '@salesforce/schema/Job_Post__c.Job_Title__c';
import LOCATION from '@salesforce/schema/Job_Post__c.Location__c';
import STATUS from '@salesforce/schema/Job_Post__c.Status__c';

export default class fetchCandidateCard extends LightningElement {
    @api recordId;

    jobTitle;
    location;
    status;

    @wire(getRecord, { recordId: '$recordId', fields: [JOB_TITLE, LOCATION, STATUS] })
    wiredJobPost({ error, data }) {
        if (data) {
            this.jobTitle = data.fields.Job_Title__c.value;
            this.location = data.fields.Location__c.value;
            this.status = data.fields.Status__c.value;
        } else if (error) {
            console.error(error);
        }
    }

    handleSearch() {
        fetchCandidates({ jobPostId: this.recordId })
            .then(result => {
                // result is FetchResponse { message, candidates }
                let variant = 'success';
                let title = 'Success';
                
                if (result.message.includes('wait at least') || result.message.includes('Please wait')) {
                    variant = 'warning';
                    title = 'Please Wait';
                } else if (result.message.includes('No new candidates found')) {
                    variant = 'info';
                    title = 'No New Candidates';
                }
                
                this.dispatchEvent(
                    new ShowToastEvent({
                        title: title,
                        message: result.message,
                        variant: variant
                    })
                );
            })
            .catch(error => {
                this.dispatchEvent(
                    new ShowToastEvent({
                        title: 'Error fetching candidates',
                        message: error.body ? error.body.message : error.message,
                        variant: 'error'
                    })
                );
            });
    }

}
