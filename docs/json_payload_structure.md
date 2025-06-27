# JSON Payload Structure

For your reference only. The following represents the JSON structure expected for payload data. 
Visual representation variations shown here in case useful for wider team(s). 


## JSON Overview:

Dev ref: Structure based on specification v0.7

![JSON Structure](assets/images/json_payload_structure_diagram_v0.7.png)

<!-- ## JSON Structure:

```json
{
    "la_code": 123, 
    "Children": {
        "la_child_id": "string",
        "mis_child_id": "string",
        "purge": false,
        "child_details": {
            "unique_pupil_number": "string",
            "former_unique_pupil_number": "string",
            "unique_pupil_number_unknown_reason": "string",
            "first_name": "string",
            "surname": "string",
            "date_of_birth": "YYYY-MM-DD",
            "expected_date_of_birth": "YYYY-MM-DD",
            "sex": "string",
            "ethnicity": "string",
            "disabilities": [
                "string"
            ],
            "postcode": "string",
            "uasc_flag": true,
            "uasc_end_date": "YYYY-MM-DD",
            "purge": false
        },
        "health_and_wellbeing": {
            "sdq_assessments": [
                {
                    "date": "YYYY-MM-DD",
                    "score": 20
                }
            ],
            "purge": false
        },
        "education_health_care_plans": [
            {
                "education_health_care_plan_id": "string",
                "request_received_date": "YYYY-MM-DD",
                "request_outcome_date": "YYYY-MM-DD",
                "assessment_outcome_date": "YYYY-MM-DD",
                "plan_start_date": "YYYY-MM-DD",
                "purge": false
            }
        ],
        "social_care_episodes": [
            {
                "social_care_episode_id": "string",
                "referral_date": "YYYY-MM-DD",
                "referral_source": "string",
                "referral_no_further_action_flag": false,
                "closure_date": "YYYY-MM-DD",
                "closure_reason": "string",
                "care_worker_details": [
                    {
                        "worker_id": "string",
                        "start_date": "YYYY-MM-DD",
                        "end_date": "YYYY-MM-DD"
                    }
                ],
                "child_and_family_assessments": [
                    {
                        "child_and_family_assessment_id": "string",
                        "start_date": "YYYY-MM-DD",
                        "authorisation_date": "YYYY-MM-DD",
                        "factors": [
                            "string"
                        ],
                        "purge": false
                    }
                ],
                "child_in_need_plans": [
                    {
                        "child_in_need_plan_id": "string",
                        "start_date": "YYYY-MM-DD",
                        "end_date": "YYYY-MM-DD",
                        "purge": false
                    }
                ],
                "section_47_assessments": [
                    {
                        "section_47_assessment_id": "string",
                        "start_date": "YYYY-MM-DD",
                        "icpc_required_flag": true,
                        "icpc_date": "YYYY-MM-DD",
                        "end_date": "YYYY-MM-DD",
                        "purge": false
                    }
                ],
                "child_protection_plans": [
                    {
                        "child_protection_plan_id": "string",
                        "start_date": "YYYY-MM-DD",
                        "end_date": "YYYY-MM-DD",
                        "purge": false
                    }
                ],
                "child_looked_after_placements": [
                    {
                        "child_looked_after_placement_id": "string",
                        "start_date": "YYYY-MM-DD",
                        "start_reason": "string",
                        "placement_type": "string",
                        "postcode": "string",
                        "end_date": "YYYY-MM-DD",
                        "end_reason": "string",
                        "change_reason": "string",
                        "purge": false
                    }
                ],
                "adoption": {
                    "initial_decision_date": "YYYY-MM-DD",
                    "matched_date": "YYYY-MM-DD",
                    "placed_date": "YYYY-MM-DD",
                    "purge": false
                },
                "care_leavers": {
                    "contact_date": "YYYY-MM-DD",
                    "activity": "string",
                    "accommodation": "string",
                    "purge": false
                },
                "purge": false
            }
        ],
        "purge": false
    }
}

``` -->