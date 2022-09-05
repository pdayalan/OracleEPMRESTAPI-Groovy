import java.nio.charset.StandardCharsets
import groovy.json.JsonSlurper

import java.io.UnsupportedEncodingException;
import java.security.MessageDigest;
import java.security.NoSuchAlgorithmException;
import java.util.Arrays;
import java.util.Base64;
import javax.crypto.Cipher;
import javax.crypto.spec.SecretKeySpec;

//Reading the Values from the Properties File
Properties props = new Properties()
File propsFile = new File('C:/Users/admin/Documents/Kscope21/PBCSDetails.properties')
props.load(propsFile.newDataInputStream())


serverUrl=props.getProperty('serverUrl')
domain=props.getProperty('domain')
SecretKey=props.getProperty('SecretKey')
username=props.getProperty('username')
Encryptedpassword=props.getProperty('password')
interopUrl=props.getProperty('interopUrl') 
InteropApiVersion="11.1.2.3.600";
apiVersion = "v1";

//**************************Decrypting of the Password ***************** 
public class AES {

  private static SecretKeySpec secretKey;
  private static byte[] key;

  public static void setKey(final String myKey) {
    MessageDigest sha = null;
    try {
      key = myKey.getBytes("UTF-8");
      sha = MessageDigest.getInstance("SHA-1");
      key = sha.digest(key);
      key = Arrays.copyOf(key, 16);
      secretKey = new SecretKeySpec(key, "AES");
    } catch (NoSuchAlgorithmException | UnsupportedEncodingException e) {
      e.printStackTrace();
    }
  }

  public static String decrypt(final String strToDecrypt, final String secret) {
    try {
      setKey(secret);
      Cipher cipher = Cipher.getInstance("AES/ECB/PKCS5PADDING");
      cipher.init(Cipher.DECRYPT_MODE, secretKey);
      return new String(cipher.doFinal(Base64.getDecoder()
        .decode(strToDecrypt)));
    } catch (Exception e) {
      System.out.println("Error while decrypting: " + e.toString());
    }
    return null;
  }
}

final String secretKey = SecretKey;
String decryptedPassword = AES.decrypt(Encryptedpassword, secretKey) ;
//*************************************************************************************************************

userCredentials = username + ":" + decryptedPassword;
println userCredentials;
basicAuth = "Basic " + javax.xml.bind.DatatypeConverter.printBase64Binary(userCredentials.getBytes())

def getResponse(is) {
	BufferedReader br = new BufferedReader(new InputStreamReader(is));
	StringBuilder sb = new StringBuilder();
	String line;
	while ((line = br.readLine()) != null) {
		sb.append(line+"\n");
	}
	br.close();
	return sb.toString();
}

def executeRequest(url, requestType, payload, contentType) {
	HttpURLConnection connection = (HttpURLConnection) url.openConnection();
	connection.setDoOutput(true);
	connection.setInstanceFollowRedirects(false);
	connection.setRequestMethod(requestType);
	connection.setRequestProperty("Content-Type", contentType);
	//           connection.setRequestProperty("charset", StandardCharsets.UTF_8);
	connection.setRequestProperty("Authorization", basicAuth);
	connection.setUseCaches(false);

	if (payload != null) {
		OutputStreamWriter writer = new OutputStreamWriter(connection.getOutputStream());
		writer.write(payload);
		writer.flush();
	}

	int statusCode
	try {
		statusCode = connection.responseCode;
	} catch (all) {
		println "Error connecting to the URL"
		System.exit(0);
	}

	def response
	if (statusCode == 200 || statusCode == 201) {
		if (connection.getContentType() != null && !connection.getContentType().startsWith("application/json")) {
			println "Error occurred in server"
			System.exit(0)
		}
		InputStream is = connection.getInputStream();
		if (is != null)
			response = getResponse(is)
	} else {
		println "Error occurred while executing request"
		println "Response error code : " + statusCode
		InputStream is = connection.getErrorStream();
		if (is != null && connection.getContentType() != null && connection.getContentType().startsWith("application/json"))
			println getJobStatusFromResponse(getResponse(is))
		System.exit(0);
	}
	connection.disconnect();
	return response;
}



/************Run Refresh Database **************/
def RunRefreshDB() {
def url;
try {
url = new URL(serverUrl +"/HyperionPlanning/rest/v3/applications/ADFIN/jobs")
println "**********************************************************"
println "Executing Refresh Database"
println "Instance : " +" https://<SERVICE_NAME>-<TENANT_NAME>.<SERVICE_TYPE>.<dcX>.oraclecloud.com" +"/HyperionPlanning/rest/v3/applications/APP Name/jobs"
} catch (MalformedURLException e) {
println "Malformed URL. Please pass valid URL"
System.exit(0);
}
payLoad = '{"jobType":"CUBE_REFRESH","jobName":"RefAppl"}'
response = executeRequest(url, "POST", payLoad, "application/json");
if (response != null) {
def object = new JsonSlurper().parseText(response)
println "Job Name :" +object.jobName
println "Job ID :" +object.jobId
println "Job Status :" +object.descriptiveStatus
println "**********************************************************"
}
}



RunRefreshDB()
