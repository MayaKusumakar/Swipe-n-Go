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
