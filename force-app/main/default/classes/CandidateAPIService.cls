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

            if (this.experience > other.experience) return -1;
            if (this.experience < other.experience) return 1;

            if (this.skillMatches > other.skillMatches) return -1;
            if (this.skillMatches < other.skillMatches) return 1;

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
            SELECT Id, Job_Title__c, Location__c, Required_Skills__c, Experience_Required__c
            FROM Job_Post__c
            WHERE Id = :jobPostId
            LIMIT 1
        ];
        if (jobPost == null) throw new AuraHandledException('Job Post not found');

        List<String> requiredSkills = jobPost.Required_Skills__c != null
            ? jobPost.Required_Skills__c.split(',')
            : new List<String>();

        // 2️⃣ Fetch existing top 35 candidates
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

        // 3️⃣ Call API
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

        // 4️⃣ Wrap API candidates
        List<Candidate__c> apiCandidates = new List<Candidate__c>();
        for (Object obj : rawCandidates) {
            Map<String, Object> cand = (Map<String, Object>) obj;
            String profileUrl = (String) cand.get('profileUrl');
            if (String.isBlank(profileUrl) || existingProfiles.contains(profileUrl)) continue;

            Decimal exp = 0;
            if (cand.containsKey('experienceYears') && cand.get('experienceYears') != null) {
                try { exp = Decimal.valueOf(String.valueOf(cand.get('experienceYears'))); } catch (Exception e) {}
            }

            String skillsStr = '';
            if (cand.containsKey('skills') && cand.get('skills') != null) {
                List<Object> sList = (List<Object>) cand.get('skills');
                List<String> temp = new List<String>();
                for (Object s : sList) temp.add((String) s);
                skillsStr = String.join(temp, ', ');
            }

            apiCandidates.add(new Candidate__c(
                Candidate_Name__c = (String) cand.get('candidateName'),
                Profile_URL__c    = profileUrl,
                Email__c          = (String) cand.get('email'),
                Phone_Number__c   = (String) cand.get('phone'),
                Skills__c         = skillsStr,
                Experience__c     = exp,
                Location__c       = (String) cand.get('location'),
                Job_Post__c       = jobPost.Id
            ));
        }

        // 5️⃣ Combine topExisting + API candidates
        List<CandidateWrapper> combined = new List<CandidateWrapper>();
        for (Candidate__c c : topExisting) combined.add(new CandidateWrapper(c, jobPost.Location__c, requiredSkills));
        for (Candidate__c c : apiCandidates) combined.add(new CandidateWrapper(c, jobPost.Location__c, requiredSkills));

        combined.sort();

        // 6️⃣ Determine new top 35
        List<Candidate__c> newTop35 = new List<Candidate__c>();
        Set<String> topProfiles = new Set<String>();
        Integer rank = 1;

        for (CandidateWrapper cw : combined) {
            Candidate__c cand = cw.candidateRec;
            cand.Rank__c = rank;
            cand.Is_Top__c = (rank <= 35);
            if (rank <= 35) newTop35.add(cand);
            if (cand.Profile_URL__c != null && rank <= 35) topProfiles.add(cand.Profile_URL__c);
            rank++;
        }

        // 7️⃣ Insert only API candidates that entered top 35
        List<Candidate__c> toInsert = new List<Candidate__c>();
        for (Candidate__c c : apiCandidates) {
            if (c.Profile_URL__c != null && topProfiles.contains(c.Profile_URL__c)) toInsert.add(c);
        }
        if (!toInsert.isEmpty()) insert toInsert;

        // 8️⃣ Update Rank & Is_Top only for top 35
        Map<Id, Candidate__c> topMap = new Map<Id, Candidate__c>();
        for (Candidate__c c : newTop35) topMap.put(c.Id, c);

        List<Candidate__c> updateList = [
            SELECT Id, Rank__c, Is_Top__c
            FROM Candidate__c
            WHERE Id IN :topMap.keySet()
        ];
        for (Candidate__c c : updateList) {
            Candidate__c updated = topMap.get(c.Id);
            c.Rank__c = updated.Rank__c;
            c.Is_Top__c = updated.Is_Top__c;
        }
        if (!updateList.isEmpty()) update updateList;

        // 9️⃣ Prepare response
        List<Candidate__c> topList = [
            SELECT Id, Candidate_Name__c, Profile_URL__c, Experience__c,
                   Skills__c, Location__c, Rank__c, Is_Top__c
            FROM Candidate__c
            WHERE Job_Post__c = :jobPostId AND Is_Top__c = true
            ORDER BY Rank__c ASC
        ];

        String message;
        if (topExisting.isEmpty() && !toInsert.isEmpty()) message = 'Best 35 candidates fetched.';
        else if (!toInsert.isEmpty()) message = toInsert.size() + ' new candidates found. Top 35 updated.';
        else message = 'No new candidates found. Top 35 unchanged.';

        FetchResponse resp = new FetchResponse();
        resp.message = message;
        resp.candidates = topList;
        return resp;
    }
}
