import requests

TOKEN = ""
URL = "https://api.github.com/graphql"

# GraphQL Query for Project
QUERY = """
{
  organization(login: "data-to-insight") {
    projectsV2(first: 10) {
      nodes {
        id
        title
        url
        items(first: 10) {
          nodes {
            content {
              ... on Issue {
                title
                url
              }
            }
          }
        }
      }
    }
  }
}
"""

HEADERS = {
    "Authorization": f"Bearer {TOKEN}",
    "Content-Type": "application/json"
}

response = requests.post(URL, headers=HEADERS, json={"query": QUERY})
data = response.json()

# Filter CSC_API_Data_Flows project (from all d2i projects)
PROJECT_NAME = "csc_api_data_flows" # note: name|string based search so name must match 1:1 

if "data" in data:
    projects = data["data"]["organization"]["projectsV2"]["nodes"]

    # Find specific project
    project = next((p for p in projects if p["title"] == PROJECT_NAME), None)

    if project:
        title = project["title"]
        url = project["url"]
        issues = project["items"]["nodes"]

        # open markdown git_dev_backlog file to write
        with open("docs/feature_backlog.md", "w") as f:
            f.write(f"# {title} Github Development Backlog\n\n")
            f.write(f"## Tasks Overview\n")
            f.write(f"### Backlog/Epic/InProg/Completed\n")
            f.write(f"[View Board]({url})\n\n")

            if issues:
                for issue in issues:
                    content = issue["content"]
                    if content:
                        issue_title = content["title"]
                        issue_url = content["url"]
                        f.write(f"- [{issue_title}]({issue_url})\n")
            else:
                f.write("_No issues found._\n")

        # Below output is console update(s) only, does not appear on resultant .md page
        print("Generated feature_backlog.md - ready to deploy/serve to front-end now")
    else:
        print(f"Project '{PROJECT_NAME}' not found.")
else:
    print("Failed to fetch project data:", data.get("errors", "Unknown error"))
