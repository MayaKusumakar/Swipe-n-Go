# PROMPT

## Swipe Feature For Users
Implement the swipe feature for Swipe-N-Go, a campus event discovery app for UC Davis students.
Students should be able to browse events through a swipe-based interface, similar to Tinder. Swiping right indicates that they're interested in an event, while swiping left skips it.
Each event card should display the event name, image, date, time, location, and a short description. Students should also be able to tap on a card to view more details.
Make the swiping experience smooth and intuitive, with animations as cards move off the screen. After swiping, the next event should automatically appear.
Focus on implementing the frontend UI and swipe functionality using our existing project structure. Keep the design clean, modern, and student-friendly.

## Camera Feature For Hosts
Event hosts should be able to use the camera to take a photo of an event flyer and automatically fill in the event details, creating an event card in the app. The scan should extract the event name and the key details: date, time, and location. It should also pull a short description if the flyer has one. The flyer photo can be used as the event card's image.
If any required detail is missing or can't be read clearly, the app should prompt the person to fill it in before continuing. Before the event is officially added to the app, the person adding it must review all of the scanned details and can edit any of them. The event is only published once they confirm.

## Recommendation Algorithm
Before starting, Users should be prompted with a short questionaire about their likes and hobbies. Nothing too long, no more than 3 questions (for example, multiple choice question about different hobbies the user is into). Use this information to recommend better activities at first.
The recommendation algorithm should start off with closely related activities or events but still recommend other non-related activies. This is so the user is able to explore things they otherwise wouldn't do.

## Saved Events and Calendar For Users
When a student swipes right on an event, it should be saved to a "My Events" list in the app. Students should be able to open this list at any time to see every event they've saved, sorted by date with the soonest events at the top. Events that have already happened should move to a separate "Past" section instead of cluttering the list.
Each saved event should show the same key details as its event card: name, image, date, time, and location. Tapping a saved event should open its full details. Students should be able to remove an event from their list if they change their mind.
From an event's details, students should be able to add it to their phone's calendar (Google Calendar or Apple Calendar) with the event name, date, time, location, and description filled in. If a host edits or cancels an event that a student has saved, the student's list should reflect the change, and canceled events should be clearly marked.
Saved events must be stored on the server and tied to the student's account, so their list stays the same across devices and app reinstalls.


The backend server must use the Google App Engine Standard Environment. Requirements include:
* Python runtime: 3.10-3.13.
* Flask web service.
* Flask Blueprints for decomposed API handling.
* An app.yaml config file.
* A .gcloudignore file that excludes unnecessary files from deployment, including virtual environments and local development artifacts.

The project should not feature:
* A hosting platform that isn't with Google App Engine.
* Replace Flask with FastAPI, Djongo, or another framework.
* Put the entire backend insode one large Flask application file.

## Security Feature
Students should only be able to sign in with a verified @ucdavis.edu Google account, so everyone using the app is part of the UC Davis community. Only approved hosts, such as club officers, departments, and campus organizations, can publish events, and other students can request host access. A student's swipes and interests should stay private, and hosts should only see the number of interested students, not their identities.
Students should be able to report events that are fake, spam, or unsafe, and any event with multiple reports should be hidden until it is reviewed. Flyer photos uploaded by hosts must be image files under a size limit, have their location metadata removed, and pass an inappropriate-content check before the event can be published.


The backend server must use the Google App Engine Standard Environment. Requirements include:
* Python runtime: 3.10-3.13.
* Flask web service.
* Flask Blueprints for decomposed API handling, with every API route verifying the user's login token and host-only routes checking the host role.
* Server-side validation and sanitization of all user input.
* Rate limiting on requests to prevent spam and abuse.
* An app.yaml config file that enforces HTTPS on all routes.
* API keys and credentials stored in Google Secret Manager.
* A .gcloudignore file that excludes unnecessary files from deployment, including virtual environments, local development artifacts, and any local secret or .env files.

The project should not feature:
* A hosting platform that isn't with Google App Engine.
* Replace Flask with FastAPI, Django, or another framework.
* Put the entire backend inside one large Flask application file.
* API keys, passwords, or other secrets stored directly in the codebase.
* Sign-in for accounts outside the @ucdavis.edu domain.
