# PowerShell CRL Monitor

### Project Description
One of the most critical components of PKI (Public Key Infrastructure) is the availability of CRLs (Certificate Revocation Lists) to validate and revoke issued certificates. Using the PowerShell CRL Monitor, you can detect at an early stage if there are any problems with your CRLs before the end entities are affected. Run the script as a scheduled automated task in the Windows Task Scheduler and receive notification via mail if there are problems with your CRLs.

* The script is configurable, allowing you to set multiple CRL Distribution Points (CDPs) and their respective expiration thresholds.

* It implements logging of CRLs status, which is good for long-term use and troubleshooting.

* The script sends alerts via mail when CRLs are approaching expiration or have already expired, which is crucial for proactive management.

### Dependencies
[PKI Solutions - PowerShell PKI Module](https://www.pkisolutions.com/tools/pspki/)

### Support
This script is provided as is, no support is provided.
