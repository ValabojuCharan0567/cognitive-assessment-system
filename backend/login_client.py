import requests


BASE_URL = "http://localhost:8000"


def login_to_server(email: str, password: str):
    """
    Sends login request to Flask backend API.
    """

    url = f"{BASE_URL}/api/login"

    payload = {
        "email": email,
        "password": password
    }

    headers = {
        "Content-Type": "application/json"
    }

    try:
        print(f"Connecting to server: {url}")

        response = requests.post(
            url,
            json=payload,
            headers=headers,
            timeout=10
        )

        print("Status Code:", response.status_code)

        response.raise_for_status()

        data = response.json()

        return data

    except requests.exceptions.Timeout:
        print("❌ Connection timed out. Check if Flask server is running.")

    except requests.exceptions.ConnectionError:
        print("❌ Cannot connect to server.")
        print("Make sure:")
        print("• Flask backend is running")
        print("• IP address is correct")
        print("• Phone and laptop are on same WiFi")

    except requests.exceptions.HTTPError as e:
        print("❌ HTTP Error:", e)

        try:
            print("Server Response:", response.json())
        except Exception:
            print("Server Response:", response.text)

    except requests.exceptions.RequestException as e:
        print("❌ Request failed:", e)

    return None


def main():

    print("---- Cognitive Assessment System Login Test ----")

    email = input("Enter email: ")
    password = input("Enter password: ")

    result = login_to_server(email, password)

    if result:
        print("\n✅ Login Response:")
        print(result)
    else:
        print("\n⚠ Login failed.")


if __name__ == "__main__":
    main()