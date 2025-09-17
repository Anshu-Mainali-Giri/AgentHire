public with sharing class CandidateAPIService {

    public class CandidateWrapper implements Comparable {
        public Map<String, Object> data;
        public Decimal experience;
        public Boolean locationPriority;
        public Integer skillMatches; // number of overlapping skills

        public CandidateWrapper(Map<String, Object> data, String jobLocation, List<String> requiredSkills) {
            this.data = data;

            // Safe experience parsing
            this.experience = 0;
            if(data.containsKey('experienceYears') && data.get('experienceYears') != null){
                Object expObj = data.get('experienceYears');
                if(expObj instanceof Integer){
                    this.experience = Decimal.valueOf((Integer)expObj);
                } else if(expObj instanceof Double){
                    this.experience = Decimal.valueOf((Double)expObj);
                } else {
                    try {
                        this.experience = Decimal.valueOf(String.valueOf(expObj));
                    } catch(Exception e){
                        this.experience = 0;
                    }
                }
            }

            // Location priority
            String candLocation = data.containsKey('location') && data.get('location') != null
                ? (String)data.get('location') : '';
            this.locationPriority = (!String.isBlank(jobLocation) && candLocation.equalsIgnoreCase(jobLocation));

            // Count skill matches
            this.skillMatches = 0;
            if(data.containsKey('skills') && data.get('skills') != null){
                List<Object> candSkills = (List<Object>) data.get('skills');
                Set<String> candSet = new Set<String>();
                for(Object s : candSkills){
                    candSet.add(s != null ? ((String)s).toLowerCase() : '');
                }
                for(String reqSkill : requiredSkills){
                    if(candSet.contains(reqSkill.toLowerCase())){
                        this.skillMatches++;
                    }
                }
            }
        }

        // Sort: location priority → experience desc → skillMatches desc
        public Integer compareTo(Object compareTo) {
            CandidateWrapper other = (CandidateWrapper) compareTo;

            if (this.locationPriority && !other.locationPriority) return -1;
            if (!this.locationPriority && other.locationPriority) return 1;

            if (this.experience > other.experience) return -1;
            if (this.experience < other.experience) return 1;

            if (this.skillMatches > other.skillMatches) return -1;
            if (this.skillMatches < other.skillMatches) return 1;

            return 0;
        }
    }

    @AuraEnabled(cacheable=false)
    public static List<Candidate__c> fetchCandidates(Id jobPostId) {
        Job_Post__c jobPost = [
            SELECT Id, Job_Title__c, Job_Description__c, Required_Skills__c,
                   Location__c, Experience_Required__c
            FROM Job_Post__c
            WHERE Id = :jobPostId
            LIMIT 1
        ];

        if(jobPost == null) throw new AuraHandledException('Job Post not found');

        Decimal expRequired = jobPost.Experience_Required__c != null ? jobPost.Experience_Required__c : 0;
        List<String> requiredSkills = jobPost.Required_Skills__c != null ? jobPost.Required_Skills__c.split(',') : new List<String>();

        // Call mock API
        Http http = new Http();
        HttpRequest req = new HttpRequest();
        req.setEndpoint('callout:LinkedInTalentAPI?jobId=' + EncodingUtil.urlEncode(jobPost.Id,'UTF-8'));
        req.setMethod('GET');
        HttpResponse res = http.send(req);

        if(res.getStatusCode() != 200) throw new AuraHandledException('API Error: ' + res.getBody());

        Map<String,Object> result = (Map<String,Object>) JSON.deserializeUntyped(res.getBody());
        List<Object> rawCandidates = (List<Object>) result.get('candidates');
        if(rawCandidates == null) rawCandidates = new List<Object>();

        List<CandidateWrapper> wrapped = new List<CandidateWrapper>();
        for(Object obj : rawCandidates){
            Map<String,Object> cand = (Map<String,Object>) obj;

            // Filter only by experience ≥ minimum
            Decimal candExp = 0;
            if(cand.containsKey('experienceYears') && cand.get('experienceYears') != null){
                Object expObj = cand.get('experienceYears');
                if(expObj instanceof Integer) candExp = Decimal.valueOf((Integer)expObj);
                else if(expObj instanceof Double) candExp = Decimal.valueOf((Double)expObj);
                else{
                    try{ candExp = Decimal.valueOf(String.valueOf(expObj)); } catch(Exception e){ candExp = 0; }
                }
            }

            if(candExp >= expRequired){
                wrapped.add(new CandidateWrapper(cand, jobPost.Location__c, requiredSkills));
            }
        }

        if(wrapped.isEmpty()) throw new AuraHandledException('No candidates found with sufficient experience');

        wrapped.sort();

        List<CandidateWrapper> topList = new List<CandidateWrapper>();
        for(Integer i=0;i<wrapped.size() && i<35;i++) topList.add(wrapped[i]);

        List<Candidate__c> toInsert = new List<Candidate__c>();
        for(CandidateWrapper cw : topList){
            Map<String,Object> cand = cw.data;

            String skillsStr = '';
            if(cand.containsKey('skills') && cand.get('skills') != null){
                List<Object> sList = (List<Object>) cand.get('skills');
                List<String> temp = new List<String>();
                for(Object s : sList) temp.add((String)s);
                skillsStr = String.join(temp, ', ');
            }

            toInsert.add(new Candidate__c(
                Candidate_Name__c = cand.containsKey('candidateName') ? (String)cand.get('candidateName') : null,
                Profile_URL__c    = cand.containsKey('profileUrl') ? (String)cand.get('profileUrl') : null,
                Email__c          = cand.containsKey('email') ? (String)cand.get('email') : null,
                Phone_Number__c   = cand.containsKey('phone') ? (String)cand.get('phone') : null,
                Skills__c         = skillsStr,
                Experience__c     = cw.experience,
                Location__c       = cand.containsKey('location') ? (String)cand.get('location') : null
            ));
        }

        insert toInsert;
        return toInsert;
    }
}
