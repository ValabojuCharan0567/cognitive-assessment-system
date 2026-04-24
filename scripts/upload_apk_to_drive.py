#!/usr/bin/env python3
import argparse
import json
import os
from pathlib import Path

from google.auth.transport.requests import Request
from google.oauth2.credentials import Credentials
from google_auth_oauthlib.flow import InstalledAppFlow
from googleapiclient.discovery import build
from googleapiclient.errors import HttpError
from googleapiclient.http import MediaFileUpload

SCOPES = ['https://www.googleapis.com/auth/drive.file']


def load_credentials(client_secrets_path: Path, token_path: Path) -> Credentials:
    creds = None
    if token_path.exists():
        creds = Credentials.from_authorized_user_file(token_path, SCOPES)
    if creds and creds.valid:
        return creds

    if creds and creds.expired and creds.refresh_token:
        creds.refresh(Request())
        return creds

    if not client_secrets_path.exists():
        raise FileNotFoundError(
            f'Google OAuth client secrets not found: {client_secrets_path}\n'
            'Create credentials in Google Cloud Console and save the JSON here.'
        )

    flow = InstalledAppFlow.from_client_secrets_file(str(client_secrets_path), SCOPES)
    creds = flow.run_local_server(port=0)

    token_path.write_text(creds.to_json())
    print(f'Wrote OAuth token to: {token_path}')
    return creds


def find_existing_file(service, folder_id: str, name: str):
    escaped_name = name.replace("'", "\\'")
    query = (
        f"name = '{escaped_name}' "
        f"and '{folder_id}' in parents "
        "and trashed = false"
    )
    response = service.files().list(q=query, spaces='drive', fields='files(id, name)').execute()
    files = response.get('files', [])
    return files[0] if files else None


def upload_file(service, file_path: Path, folder_id: str, mime_type: str, existing_file_id: str | None = None):
    file_metadata = {
        'name': file_path.name,
        'parents': [folder_id],
    }
    media = MediaFileUpload(str(file_path), mimetype=mime_type, resumable=True)
    if existing_file_id:
        request = service.files().update(fileId=existing_file_id, media_body=media, fields='id, name')
    else:
        request = service.files().create(body=file_metadata, media_body=media, fields='id, name')
    return request.execute()


def main() -> int:
    parser = argparse.ArgumentParser(
        description='Upload or update an APK file to Google Drive using the Drive API.'
    )
    parser.add_argument('--file', '-f', required=True, help='Path to the APK file to upload.')
    parser.add_argument('--folder-id', '-d', required=True, help='Google Drive folder ID to upload into.')
    parser.add_argument(
        '--credentials', '-c', default='scripts/drive_credentials.json',
        help='Path to Google OAuth client secrets JSON.',
    )
    parser.add_argument(
        '--token', '-t', default='scripts/drive_token.json',
        help='Path to store Google Drive OAuth token JSON.',
    )
    args = parser.parse_args()

    file_path = Path(args.file).expanduser().resolve()
    if not file_path.exists():
        print(f'APK file not found: {file_path}')
        return 2

    credentials_path = Path(args.credentials).expanduser().resolve()
    token_path = Path(args.token).expanduser().resolve()
    try:
        creds = load_credentials(credentials_path, token_path)
    except Exception as error:
        print(f'Failed to load Google credentials: {error}')
        return 1

    try:
        service = build('drive', 'v3', credentials=creds)
        existing = find_existing_file(service, args.folder_id, file_path.name)
        if existing:
            print(f'Updating existing file: {existing["name"]} ({existing["id"]})')
            result = upload_file(service, file_path, args.folder_id, 'application/vnd.android.package-archive', existing_file_id=existing['id'])
        else:
            print(f'Uploading new file: {file_path.name}')
            result = upload_file(service, file_path, args.folder_id, 'application/vnd.android.package-archive')
        print('Upload complete.')
        print(f'File ID: {result.get("id")}')
        return 0
    except HttpError as error:
        print(f'Google Drive API error: {error}')
        return 1


if __name__ == '__main__':
    raise SystemExit(main())
