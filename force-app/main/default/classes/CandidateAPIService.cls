public with sharing class CandidateAPIService {

    public class CandidateWrapper implements Comparable {
        public Candidate__c candidateRec;
        public Decimal experience;
        public Boolean locationPriority;
        public Integer skillMatches;

        public CandidateWrapper(Candidate__c cand, String jobLocation, List<String> requiredSkills) {
            this.candidateRec = cand;
            this.experience = cand.Experience__c != null ? cand.Experience__c : 0;
            String candLocation = cand.Location__c != null ? cand.Location__c : '';
            this.locationPriority = (!String.isBlank(jobLocation) && candLocation.equalsIgnoreCase(jobLocation));
            this.skillMatches = 0;

            if (cand.Skills__c != null) {
                List<String> candSkills = cand.Skills__c.split(',');
                Set<String> candSet = new Set<String>();
                for (String s : candSkills) {
                    if (s != null) candSet.add(s.trim().toLowerCase());
                }
                for (String reqSkill : requiredSkills) {
                    if (candSet.contains(reqSkill.trim().toLowerCase())) this.skillMatches++;
                }
            }
        }

        public Integer compareTo(Object otherObj) {
            CandidateWrapper other = (CandidateWrapper) otherObj;

            if (this.locationPriority && !other.locationPriority) return -1;
            if (!this.locationPriority && other.locationPriority) return 1;

            if (this.skillMatches > other.skillMatches) return -1;
            if (this.skillMatches < other.skillMatches) return 1;

            if (this.experience > other.experience) return -1;
            if (this.experience < other.experience) return 1;

            return 0;
        }
    }

    public class FetchResponse {
        @AuraEnabled public String message { get; set; }
        @AuraEnabled public List<Candidate__c> candidates { get; set; }
    }

    @AuraEnabled(cacheable=false)
    public static FetchResponse fetchCandidates(Id jobPostId) {

        // 1️⃣ Fetch Job Post
        Job_Post__c jobPost = [
            SELECT Id, Job_Title__c, Location__c, Required_Skills__c, Experience_Required__c, 
                   First_Fetch_Date__c, Last_Fetch_Time__c
            FROM Job_Post__c
            WHERE Id = :jobPostId
            LIMIT 1
        ];
        if (jobPost == null) throw new AuraHandledException('Job Post not found');

        List<String> requiredSkills = jobPost.Required_Skills__c != null
            ? jobPost.Required_Skills__c.split(',')
            : new List<String>();

        // 2️⃣ Check fetch eligibility and determine limit
        DateTime now = DateTime.now();
        Integer fetchLimit = 0;
        String message = '';
        
        if (jobPost.First_Fetch_Date__c == null) {
            // First fetch - 30 candidates
            fetchLimit = 30;
            jobPost.First_Fetch_Date__c = now;
            jobPost.Last_Fetch_Time__c = now;
        } else if (jobPost.Last_Fetch_Time__c != null) {
            Long minutesDiff = (now.getTime() - jobPost.Last_Fetch_Time__c.getTime()) / (1000 * 60);
            Long hoursDiff = (now.getTime() - jobPost.Last_Fetch_Time__c.getTime()) / (1000 * 60 * 60);
            Long totalHours = (now.getTime() - jobPost.First_Fetch_Date__c.getTime()) / (1000 * 60 * 60);
            
            if (minutesDiff < 5) {
                message = 'No new candidates found.';
                fetchLimit = 0;
            } else if (hoursDiff < 12) {
                message = 'Please wait at least 12 hours before fetching new candidates.';
                fetchLimit = 0;
            } else if (totalHours >= 12 && totalHours < 24) {
                // 12-24 hours after first fetch - 10 candidates
                fetchLimit = 10;
                jobPost.Last_Fetch_Time__c = now;
            } else if (totalHours >= 24 && totalHours < 36) {
                // 24+ hours after first fetch - 10 candidates
                fetchLimit = 10;
                jobPost.Last_Fetch_Time__c = now;
            } else {
                // After 36+ hours - no more fetching
                message = 'No new candidates found.';
                fetchLimit = 0;
            }
        }
        
        if (fetchLimit == 0) {
            FetchResponse resp = new FetchResponse();
            resp.message = message;
            resp.candidates = [
                SELECT Id, Candidate_Name__c, Profile_URL__c, Experience__c,
                       Skills__c, Location__c, Rank__c, Is_Top__c
                FROM Candidate__c
                WHERE Job_Post__c = :jobPostId AND Is_Top__c = true
                ORDER BY Rank__c ASC
            ];
            return resp;
        }

        // 3️⃣ Fetch existing candidates
        List<Candidate__c> topExisting = [
            SELECT Id, Candidate_Name__c, Profile_URL__c, Experience__c, Skills__c, Location__c,
                   Rank__c, Is_Top__c
            FROM Candidate__c
            WHERE Job_Post__c = :jobPostId AND Is_Top__c = true
        ];
        Set<String> existingProfiles = new Set<String>();
        for (Candidate__c c : topExisting) {
            if (c.Profile_URL__c != null) existingProfiles.add(c.Profile_URL__c);
        }

        // 4️⃣ Call API
        Http http = new Http();
        HttpRequest req = new HttpRequest();
        req.setEndpoint('callout:LinkedInTalentAPI?jobId=' + EncodingUtil.urlEncode(jobPost.Id, 'UTF-8'));
        req.setMethod('GET');
        HttpResponse res = http.send(req);

        if (res.getStatusCode() != 200) {
            throw new AuraHandledException('API Error: ' + res.getStatusCode());
        }

        Map<String, Object> result = (Map<String, Object>) JSON.deserializeUntyped(res.getBody());
        List<Object> rawCandidates = (List<Object>) result.get('candidates');
        if (rawCandidates == null) rawCandidates = new List<Object>();

        // 5️⃣ Wrap and sort API candidates with experience filter
        List<CandidateWrapper> allApiCandidates = new List<CandidateWrapper>();
        for (Object obj : rawCandidates) {
            Map<String, Object> cand = (Map<String, Object>) obj;
            String profileUrl = (String) cand.get('profileUrl');
            if (String.isBlank(profileUrl) || existingProfiles.contains(profileUrl)) continue;

            Decimal exp = 0;
            if (cand.containsKey('experienceYears') && cand.get('experienceYears') != null) {
                try { exp = Decimal.valueOf(String.valueOf(cand.get('experienceYears'))); } catch (Exception e) {}
            }
            
            // Filter by minimum experience if specified
            if (jobPost.Experience_Required__c != null && exp < jobPost.Experience_Required__c) {
                continue;
            }

            String skillsStr = '';
            if (cand.containsKey('skills') && cand.get('skills') != null) {
                List<Object> sList = (List<Object>) cand.get('skills');
                List<String> temp = new List<String>();
                for (Object s : sList) temp.add((String) s);
                skillsStr = String.join(temp, ', ');
            }

            Candidate__c newCand = new Candidate__c(
                Candidate_Name__c = (String) cand.get('candidateName'),
                Profile_URL__c    = profileUrl,
                Email__c          = (String) cand.get('email'),
                Phone_Number__c   = (String) cand.get('phone'),
                Skills__c         = skillsStr,
                Experience__c     = exp,
                Location__c       = (String) cand.get('location'),
                Job_Post__c       = jobPost.Id
            );
            allApiCandidates.add(new CandidateWrapper(newCand, jobPost.Location__c, requiredSkills));
        }
        
        // Create mixed experience distribution
        List<Candidate__c> limitedApiCandidates = new List<Candidate__c>();
        if (!allApiCandidates.isEmpty()) {
            // Group by location priority first
            List<CandidateWrapper> locationMatch = new List<CandidateWrapper>();
            List<CandidateWrapper> locationOther = new List<CandidateWrapper>();
            
            for (CandidateWrapper cw : allApiCandidates) {
                if (cw.locationPriority) {
                    locationMatch.add(cw);
                } else {
                    locationOther.add(cw);
                }
            }
            
            // Sort each group by skills, then experience
            locationMatch.sort();
            locationOther.sort();
            
            // Take mixed experience from location matches first
            Integer taken = 0;
            Integer maxPerGroup = Math.max(1, fetchLimit / 4); // Take varied candidates
            
            // Take from location matches with experience variety
            for (Integer i = 0; i < locationMatch.size() && taken < fetchLimit; i += Math.max(1, locationMatch.size() / maxPerGroup)) {
                limitedApiCandidates.add(locationMatch[i].candidateRec);
                taken++;
            }
            
            // Fill remaining with other locations
            for (Integer i = 0; i < locationOther.size() && taken < fetchLimit; i += Math.max(1, locationOther.size() / maxPerGroup)) {
                limitedApiCandidates.add(locationOther[i].candidateRec);
                taken++;
            }
            
            // If still need more, take sequentially
            for (CandidateWrapper cw : allApiCandidates) {
                if (taken >= fetchLimit) break;
                Boolean alreadyAdded = false;
                for (Candidate__c added : limitedApiCandidates) {
                    if (added.Profile_URL__c == cw.candidateRec.Profile_URL__c) {
                        alreadyAdded = true;
                        break;
                    }
                }
                if (!alreadyAdded) {
                    limitedApiCandidates.add(cw.candidateRec);
                    taken++;
                }
            }
        }

        // 6️⃣ Combine existing + limited new candidates
        List<CandidateWrapper> combined = new List<CandidateWrapper>();
        for (Candidate__c c : topExisting) combined.add(new CandidateWrapper(c, jobPost.Location__c, requiredSkills));
        for (Candidate__c c : limitedApiCandidates) combined.add(new CandidateWrapper(c, jobPost.Location__c, requiredSkills));

        combined.sort();

        // 7️⃣ Determine new rankings
        List<Candidate__c> newTopCandidates = new List<Candidate__c>();
        Integer rank = 1;
        for (CandidateWrapper cw : combined) {
            cw.candidateRec.Rank__c = rank;
            cw.candidateRec.Is_Top__c = true;
            newTopCandidates.add(cw.candidateRec);
            rank++;
        }

        // 8️⃣ Update Job Post and Insert new candidates
        update jobPost;
        if (!limitedApiCandidates.isEmpty()) insert limitedApiCandidates;

        // 9️⃣ Update existing candidates
        List<Candidate__c> toUpdate = new List<Candidate__c>();
        for (Candidate__c c : topExisting) {
            for (Candidate__c updated : newTopCandidates) {
                if (c.Id == updated.Id) {
                    c.Rank__c = updated.Rank__c;
                    toUpdate.add(c);
                    break;
                }
            }
        }
        if (!toUpdate.isEmpty()) update toUpdate;

        // 🔟 Prepare response
        List<Candidate__c> finalList = [
            SELECT Id, Candidate_Name__c, Profile_URL__c, Experience__c,
                   Skills__c, Location__c, Rank__c, Is_Top__c
            FROM Candidate__c
            WHERE Job_Post__c = :jobPostId AND Is_Top__c = true
            ORDER BY Rank__c ASC
        ];

        FetchResponse resp = new FetchResponse();
        resp.message = limitedApiCandidates.size() + ' best candidates fetched and ranked.';
        resp.candidates = finalList;
        return resp;
    }
}
