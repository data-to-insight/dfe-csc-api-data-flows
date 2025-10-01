# Playbook - Troubleshooting & FAQ

> Note: Details here are currently *Powershell specific*, we're working on the Python/CLI related version as this was a more recent development within our project solution. 

---

## Log SSD/API support tickets  

 - **Phase1 & Phase 2 LAs/deployment teams should [Log deployment bugs, required changes or running issues via](https://github.com/data-to-insight/dfe-csc-api-data-flows/issues) - the basic/free Github account may be required for this**  
 - **LA colleagues are also encouraged to send the project your [general feedback, or your deployment requirements](https://forms.gle/rHTs5qJn8t6h6tQF8)**  

---

### **How do I check my PowerShell version?**
- Run:
$PSVersionTable.PSVersion


### **How do I check if the SQL Server is accessible?**
- Run:
ping YourSQLServerInstance


### **The script says `Invoke-Sqlcmd` is not recognised.**
- Ensure the **SqlServer** module is installed:
Install-Module -Name SqlServer -AllowClobber -Scope CurrentUser

### **I'm getting SSL/TLS errors when connecting to SQL Server.**
- Add the `-TrustServerCertificate` parameter to `Invoke-Sqlcmd` commands in the script.

### **The script runs but doesn’t send data.**
- Ensure `$testingMode` is set to `$false` for production.
- Verify the **API token** and **endpoint URL**.

### **How do I modify the database details for another Local Authority?**
- Update the `$server` and `$database` variables to match the Local Authority’s reporting instance.
- Verify that the `ssd_api_data_staging` table exists in their database.

---

## **PowerShell Module Issues**

### **1. Verify Installation Location**
- The `Install-Module` command installs the module to a user-specific directory when using `-Scope CurrentUser`.  
- Check if the module is installed in the expected directory:
Get-ChildItem "$env:USERPROFILE\Documents\WindowsPowerShell\Modules\SqlServer"

- If files exist, the module is installed correctly but may not be loading.
- If no files are found, **reinstall** the module and ensure no errors occur.


### **2. Import the Module Manually**
- Try importing the module explicitly:
Import-Module "$env:USERPROFILE\Documents\WindowsPowerShell\Modules\SqlServer\SqlServer.psd1"

- If this works, PowerShell isn't searching the correct module directory.
- If it fails, check if the module files exist in the specified location.


### **3. Check Execution Policy**
- PowerShell's execution policy might be preventing module imports. Check the policy:
Get-ExecutionPolicy

- If set to `Restricted`, change it to `RemoteSigned` temporarily:
Set-ExecutionPolicy -Scope CurrentUser -ExecutionPolicy RemoteSigned


### **4. Reinstall the Module**
- If the module still doesn’t appear, force a reinstallation:
Install-Module -Name SqlServer -Force -AllowClobber -Scope CurrentUser


### **5. Check PowerShell Version**
- Ensure you are running PowerShell 5.1 or later:
$PSVersionTable.PSVersion

- If your version is outdated, upgrade to the latest version:
- **Windows 10/11:** Install the latest version of PowerShell (7.x) via the Microsoft Store or from the [PowerShell GitHub releases](https://github.com/PowerShell/PowerShell).

### **6. Verify Modules Directory**
- Ensure that PowerShell is correctly searching the user-specific modules directory:
$env:PSModulePath -split ';'


- Look for a path similar to: `C:\Users\<YourUser>\Documents\WindowsPowerShell\Modules`
- If the path is missing, add it manually:
  ```
  $env:PSModulePath += ";$env:USERPROFILE\Documents\WindowsPowerShell\Modules"
  ```

### **7. Use Administrator Privileges**
- If all else fails, try installing the module for all users with admin privileges:
1. Open **PowerShell as Administrator**.
2. Run:
   ```
   Install-Module -Name SqlServer -AllowClobber -Scope AllUsers
   ```
- This installs the module in the `Program Files` directory, making it accessible to all users.

---

## **Testing `Invoke-Sqlcmd`**

- Once the module is installed (or if already installed), verify connectivity to your SQL Server:
Invoke-Sqlcmd -Query "SELECT 1 AS Test" -ServerInstance "YourServerName"
### **Expected Output:**
Test
1


### **Connectivity Issues:**

1. **SQL Server Connectivity:**
   - Ensure `YourServerName` is accessible. Test with:
     ```
     ping YourServerName
     ```

2. **SQL Server Instance Name:**
   - If `YourServerName` is a **named instance**, include it:
     ```
     Invoke-Sqlcmd -Query "SELECT 1 AS Test" -ServerInstance "YourServerName\InstanceName"
     ```

3. **SQL Server Port:**
   - If SQL Server is **not running on the default port (1433)**, include the port:
     ```
     Invoke-Sqlcmd -Query "SELECT 1 AS Test" -ServerInstance "YourServerName,1433"
     ```

4. **Firewall Rules:**
   - Ensure your machine has permission to connect to the SQL Server.
   - Check for **firewall rules blocking the connection**.

---