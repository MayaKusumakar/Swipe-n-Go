# Swipe-n-Go

**Group Name:** Swipe-n-Go

**Group Members:** Maya Kusumakar, Evelyn, Haylie, Angus, Beale, Noah Wong, Anat

**Github Repo:** https://github.com/MayaKusumakar/Swipe-n-GoLinks to an external site.

**Elevator Pitch:** My app idea is called Swipe n Go, it's basically Tinder but for finding activities to do rather than people to date. The point of the app is to help UC Davis students find things going on around them. Whether that be club general meetings, a farmers market, a house show, a trivia night, etc. A user would swipe right on activities that they want to do and left on activities that they don't want to do. Over time, the app would learn about the user and order activity recommendations in order of most fitting to least fitting. This app would also allow filtering based on budget, distance, amount of free time, etc. 

**Short Writeup:** We plan to build an app that serves the same function as mentioned above. We plan to build an app that has two parts (the event host side and the user side). The event host side will be able to upload fliers (ai will take this information and automate inputting it into the database), manually enter events, etc. The user side will have the ideas show up on their feed and will be able to swipe right and add to calendar/ swipe left and reject. There will also be a geographic map view that shows users' activities based on location as well. Users will also be able to have friends and see what their friends are going to. Since we have a lot of people in our group, we plan to make the app scope larger than just UC Davis, we want this to work in different areas and we also plan to make the technical side more advanced. We plan to have a very complex personalization algorithm behind the scenes for users and also a complex method of scraping events so that we're not only reliant on the producer side of our app.  

**His Comments:** Overall this looks like a good project. My suggestion is to focus on one event type. Parties, football game tailgates, pickup sports, whatever, and really try to nail that. I can be convinced that a general event app is useful, but I suspect you'll get much deeper insight and build a better project if you can narrow down the types of events you're interested in so you can focus on the hosts / guests for this type of event.


Description:

Requirements:
-

API keys:
Put these in a .env file (don't commit it).
-

Running the server:
Backend is Flask on Google App Engine Standard (Python 3.12) with Firestore in Datastore Mode. Run these in WSL/Linux/macOS from `backend/`.
1. Setup: `python3 -m venv .venv && .venv/bin/pip install -r requirements-dev.txt`
   Quickest local demo, no Google Cloud needed: `EVENT_STORE=memory .venv/bin/flask --app main run --host 0.0.0.0 --port 8080`. This serves built-in DEVELOPMENT sample events from memory. Otherwise:
2. Point it at Datastore (see `backend/.env.example`): either `gcloud auth application-default login` plus `export GOOGLE_CLOUD_PROJECT=<project-id>`, or the local emulator (`gcloud beta emulators datastore start`, then `export DATASTORE_EMULATOR_HOST=localhost:8081 GOOGLE_CLOUD_PROJECT=<any-id>`).
3. `export DATASTORE_NAMESPACE=dev` and load sample data: `.venv/bin/python -m scripts.seed_dev_events` (development data only, marked `is_seed_data`).
4. `.venv/bin/flask --app main run --host 0.0.0.0 --port 8080`
5. Check: `curl localhost:8080/health` and `curl localhost:8080/api/events`. Without Datastore configured, `/api/events` returns a 503 JSON error.

Deploying to App Engine (needs the gcloud CLI and a GCP project with Datastore Mode enabled):
1. `cd backend && gcloud app deploy --project <project-id>`
2. `curl https://<project-id>.appspot.com/health`

Running the client:
Android app in `android/` (Kotlin + Jetpack Compose, minSdk 26). Needs Android Studio (or the Android SDK plus JDK 17+).
Note: Gradle on Windows can't build from a `\\wsl.localhost\...` path. If your clone lives in WSL, build from a Windows-side clone/copy.
1. Open the `android/` folder in Android Studio and let it sync (it creates `local.properties` with your SDK path).
2. Start the backend (above) on port 8080 and start the emulator, or plug in a phone with USB debugging.
3. Run `adb reverse tcp:8080 tcp:8080`. This is needed once per emulator boot or phone connection. It makes the device's `localhost:8080` (the default backend URL) tunnel to your computer. Android 17 blocks apps targeting SDK 37 from reaching `10.0.2.2` or LAN IPs without a special permission, so the classic `10.0.2.2` trick doesn't work.
4. Run the `app` configuration in Android Studio, or `./gradlew installDebug`.
5. Using a different backend (e.g. App Engine): set `swipeNGo.apiBaseUrl` in `android/gradle.properties`, or build with `./gradlew installDebug -PswipeNGo.apiBaseUrl=https://<project-id>.appspot.com`.

Running tests:
Backend: from `backend/`, run `.venv/bin/python -m pytest`
Client unit tests: from `android/`, run `./gradlew testDebugUnitTest` (`gradlew.bat` on Windows)
Client UI tests (need a running emulator or device): `./gradlew connectedDebugAndroidTest`

Test login:
username -
password -


