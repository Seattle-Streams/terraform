# v1.9
# TODO: Determine whether we should be using oauth2client (deprecated) or a different library

import os
import httplib2
import boto3

from googleapiclient import discovery
from oauth2client import client
from oauth2client import tools
from oauth2client.file import Storage
import googleapiclient.errors

SCOPES = ["https://www.googleapis.com/auth/youtube.force-ssl", "https://www.googleapis.com/auth/youtube.readonly"]
API_SERVICE_NAME = "youtube"
API_VERSION = "v3"
# CLIENT_SECRET_FILE = "client_secret.json"
CREDENTIAL_FILE = "credentials.json"
# AUTH_CODE = ""
# Remember to verify authenticity of auth code!
# https://developers.google.com/identity/sign-in/web/backend-auth
# use verify_oauth2_token 

# MESSAGE = "Hello World!!"

s3 = boto3.client('s3')
BUCKET_NAME = 'process-messages-builds'

# getLiveChatID gets the liveChatID of the currently streaming broadcast
def getLiveChatID(youtubeObject) -> str:
    request = youtubeObject.liveBroadcasts().list(
        part="snippet", # available: snippet, status broadcastContent (spelling?)
        broadcastType="all",
        mine=True # only the broadcasts corresponding to authenticated user
    )
    response = request.execute()
    # TODO: sort this list
    liveChatID = response['items'][0]['snippet']['liveChatId']
    return liveChatID

# postMessage inserts the specified message into the livechat corresponding with the given liveChatID
def postMessage(youtubeObject, liveChatID, message) -> str:
    request = youtubeObject.liveChatMessages().insert(
        part="snippet",
        body={
          "snippet": {
            "liveChatId": liveChatID,
            "type": "textMessageEvent",
            "textMessageDetails": {
              "messageText": message
            }
          }
        }
    )
    response = request.execute()

    return response


# for now, gets credentials if they exist, or breaks
def getStoredCredentials():
    
    # pull credentials from S3    
    local_file_name = "/tmp/" + CREDENTIAL_FILE
    s3.download_file(BUCKET_NAME, CREDENTIAL_FILE, local_file_name)
    
    store = Storage(local_file_name)
    
    credentials = store.locked_get()
    # if not credentials or credentials.invalid:

        # Storage object  class:
        # https://oauth2client.readthedocs.io/en/latest/_modules/oauth2client/file.html#Storage
        # Set store with credentials.set_store(store):
        # https://oauth2client.readthedocs.io/en/latest/_modules/oauth2client/client.html#OAuth2Credentials.set_store
        
        # note: authcode is currently set
        # Exchange auth code for access token, refresh token, and ID token
        # credentials = client.credentials_from_clientsecrets_and_code(
        #     CLIENT_SECRET_FILE,
        #     SCOPES,
        #     AUTH_CODE)
        # store.locked_put(credentials)

    # unclear what the value of this line is
    credentials.set_store(store)
    return credentials


# auth authenticates with the provided client secrets file, scope, and authorization code
# returns youtube client object
def auth():
    
    # TODO: implement in api gateway
    # (Receive auth_code by HTTPS POST)

    # TODO: implement in api gateway
    # If this request does not have `X-Requested-With` header, this could be a CSRF
    # if not request.headers.get('X-Requested-With'):
    #     abort(403)

    
    # TODO: Disable OAuthlib's HTTPS verification when running locally.
    # *DO NOT* leave this option enabled in production.
    os.environ["OAUTHLIB_INSECURE_TRANSPORT"] = "1"

    credentials = getStoredCredentials()

    # changes methods of http object to add appropriate auth headers
    httpAuth = credentials.authorize(httplib2.Http())

    if credentials.access_token_expired:
        credentials.refresh(httplib2.Http())
        httpAuth = credentials.authorize(httplib2.Http())
        

    youtubeService = discovery.build(
        API_SERVICE_NAME, API_VERSION, http=httpAuth)

    return youtubeService

def ProcessMessage(event, context):
    message = event["body"]

    youtubeObject = auth()
    liveChatID = getLiveChatID(youtubeObject)
    response = postMessage(youtubeObject, liveChatID, message)
    print('Logging YouTube response', response)
    return {'statusCode': 200}