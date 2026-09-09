import json
import os

from dotenv import load_dotenv
from flask import Flask, jsonify, request
from flask_cors import CORS
from google import genai
from google.genai import types
from pydantic import BaseModel, Field

load_dotenv()

# gemini-2.5-flash is Google's confirmed low-latency choice for this service.
# Note for whoever reads this later: Google has slated 2.5 Flash for shutdown
# no earlier than 2026-10-16, replaced by 3.5 Flash - fine for the hackathon
# timeline, but if this service is still running after that date, swap this
# one constant.
MODEL_NAME = "gemini-2.5-flash"

GEMINI_API_KEY = os.environ.get("GEMINI_API_KEY")

app = Flask(__name__)
CORS(app)

_client = genai.Client(api_key=GEMINI_API_KEY) if GEMINI_API_KEY else None


class ParsedCV(BaseModel):
    first_name: str | None = Field(default=None, description="Extracted first name, or null if not found")
    last_name: str | None = Field(default=None, description="Extracted last name, or null if not found")
    professional_headline: str = Field(
        description="A generated 1-sentence summary of their career/student status"
    )
    skills: list[str] = Field(description="Array of technical and soft skills")
    education_summary: str = Field(description="Extracted education details")


SYSTEM_PROMPT = (
    "You are the Richfield Connect Onboarding Assistant. You help students and alumni "
    "build elite professional profiles. Keep responses concise, encouraging, and highly "
    "specific to the user's current profile data. If their profile is missing skills, "
    "suggest specific ones based on their headline."
)


def _require_client() -> genai.Client:
    if _client is None:
        raise RuntimeError("GEMINI_API_KEY is not configured on the server")
    return _client


@app.get("/health")
def health():
    return jsonify(
        status="ok",
        gemini_configured=bool(GEMINI_API_KEY),
        supabase_configured=bool(
            os.environ.get("SUPABASE_URL") and os.environ.get("SUPABASE_SERVICE_ROLE_KEY")
        ),
    )


@app.post("/api/parse-cv")
def parse_cv():
    data = request.get_json(silent=True) or {}
    cv_text = data.get("cv_text")
    if not isinstance(cv_text, str) or not cv_text.strip():
        return jsonify(error="cv_text is required and must be a non-empty string"), 400

    try:
        client = _require_client()
        response = client.models.generate_content(
            model=MODEL_NAME,
            contents=(
                "Extract structured profile information from the following CV/resume "
                "text. If a field genuinely cannot be determined, use null (for the name "
                "fields) or an empty array/string as appropriate - never invent "
                "information that isn't actually present in the text.\n\n"
                f"CV TEXT:\n{cv_text}"
            ),
            config=types.GenerateContentConfig(
                response_mime_type="application/json",
                response_schema=ParsedCV,
            ),
        )
        if not response.text:
            return jsonify(error="The model returned an empty response"), 502
        parsed = ParsedCV.model_validate_json(response.text)
        return jsonify(parsed.model_dump()), 200
    except RuntimeError as e:
        return jsonify(error=str(e)), 500
    except Exception as e:
        app.logger.exception("parse_cv failed")
        return jsonify(error=f"Failed to parse CV: {e}"), 500


@app.post("/api/chat")
def chat():
    data = request.get_json(silent=True) or {}
    message = data.get("message")
    user_profile = data.get("user_profile", {})

    if not isinstance(message, str) or not message.strip():
        return jsonify(error="message is required and must be a non-empty string"), 400
    if not isinstance(user_profile, dict):
        return jsonify(error="user_profile must be a JSON object"), 400

    try:
        client = _require_client()
        response = client.models.generate_content(
            model=MODEL_NAME,
            contents=(
                f"The user's current profile state (JSON):\n{json.dumps(user_profile)}\n\n"
                f"The user says: {message}"
            ),
            config=types.GenerateContentConfig(system_instruction=SYSTEM_PROMPT),
        )
        if not response.text:
            return jsonify(error="The model returned an empty response"), 502
        return jsonify(reply=response.text), 200
    except RuntimeError as e:
        return jsonify(error=str(e)), 500
    except Exception as e:
        app.logger.exception("chat failed")
        return jsonify(error=f"Failed to generate reply: {e}"), 500


@app.errorhandler(404)
def not_found(_e):
    return jsonify(error="Not found"), 404


@app.errorhandler(405)
def method_not_allowed(_e):
    return jsonify(error="Method not allowed"), 405


if __name__ == "__main__":
    app.run(debug=True)
