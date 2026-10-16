import { createClient } from "npm:@supabase/supabase-js@2";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers":
    "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

const allowedContinents = new Set([
  "Africa",
  "Antarctica",
  "Asia",
  "Europe",
  "North America",
  "Oceania",
  "South America",
]);

// ISO 3166-1 alpha-2 country/territory codes grouped by continent.
// This avoids silently rejecting countries simply because they were not in
// the original short, hand-picked mapping.
const continentByCountryCode: Record<string, string> = {};
const countryCodesByContinent: Record<string, string> = {
  Africa: `
    DZ AO BJ BW BF BI CV CM CF TD KM CG CD CI DJ EG GQ ER SZ ET GA GM GH GN GW
    KE LS LR LY MG MW ML MR MU MA MZ NA NE NG RW ST SN SC SL SO ZA SS SD TZ TG
    TN UG EH ZM ZW RE YT SH
  `,
  Antarctica: `AQ BV HM TF`,
  Asia: `
    AF AM AZ BH BD BT BN KH CN CY GE HK MO IN ID IR IQ IL JP JO KZ KW KG LA LB MY MV IO
    MN MM NP KP OM PK PS PH QA SA SG KR LK SY TW TJ TH TL TR TM AE UZ VN YE
  `,
  Europe: `
    AX AL AD AT BY BE BA BG HR CZ DK EE FO FI FR DE GI GR GG VA HU IS IE IM IT JE
    XK LV LI LT LU MT MD MC ME NL MK NO PL PT RO RU SM RS SK SI ES SE CH UA GB SJ
  `,
  "North America": `
    AI AG AW BS BB BZ BM BQ VG CA KY CR CU CW DM DO SV GL GD GP GT HT HN JM MQ UM
    MX MS NI PA PR BL KN LC MF PM VC SX TT TC US VI
  `,
  Oceania: `
    AS AU CX CC CK FJ PF GU KI MH FM NR NC NZ NU NF MP PW PG PN WS SB TK TO TV
    VU WF
  `,
  "South America": `
    AR BO BR CL CO EC FK GF GS GY PY PE SR UY VE
  `,
};

for (const [continent, codes] of Object.entries(countryCodesByContinent)) {
  for (const code of codes.trim().split(/\s+/)) {
    if (code) continentByCountryCode[code] = continent;
  }
}

function respond(body: unknown, status = 200) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...corsHeaders, "Content-Type": "application/json" },
  });
}

function isAdult(dob: string): boolean {
  if (!/^\d{4}-\d{2}-\d{2}$/.test(dob)) return false;

  const parsed = new Date(`${dob}T00:00:00.000Z`);
  if (
    Number.isNaN(parsed.getTime()) ||
    parsed.toISOString().slice(0, 10) !== dob
  ) {
    return false;
  }

  const now = new Date();
  const cutoff = new Date(Date.UTC(
    now.getUTCFullYear() - 18,
    now.getUTCMonth(),
    now.getUTCDate(),
  ));

  return parsed.getTime() <= cutoff.getTime();
}

async function reverseGeocode(latitude: number, longitude: number) {
  const apiKey = Deno.env.get("GEOAPIFY_API_KEY");

  if (!apiKey) {
    throw new Error("GEOAPIFY_API_KEY secret is not configured");
  }

  const url = new URL("https://api.geoapify.com/v1/geocode/reverse");
  url.searchParams.set("lat", String(latitude));
  url.searchParams.set("lon", String(longitude));
  url.searchParams.set("type", "country");
  url.searchParams.set("format", "json");
  url.searchParams.set("apiKey", apiKey);

  const response = await fetch(url, {
    headers: { Accept: "application/json" },
  });

  if (!response.ok) {
    const details = await response.text().catch(() => "");
    console.error("Geoapify reverse-geocoding failed", {
      status: response.status,
      statusText: response.statusText,
      details: details.slice(0, 500),
    });
    throw new Error(`Reverse geocoding failed (HTTP ${response.status})`);
  }

  const data = await response.json();
  const result = data?.results?.[0];

  if (!result?.country || !result?.country_code) {
    console.error("Geoapify returned no country result", {
      resultCount: data?.results?.length ?? 0,
    });
    throw new Error("Could not determine a country from this location");
  }

  const countryCode = String(result.country_code).toUpperCase();
  const continent = continentByCountryCode[countryCode] ?? "";

  if (!allowedContinents.has(continent)) {
    console.error("Could not map country to an allowed continent", {
      countryCode,
    });
    throw new Error("Could not determine the continent for this country");
  }

  return {
    country_code: countryCode,
    country: String(result.country),
    continent,
  };
}

Deno.serve(async (req: Request) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }

  if (req.method !== "POST") {
    return respond({ error: "Method not allowed" }, 405);
  }

  try {
    const authorization = req.headers.get("Authorization");
    if (!authorization?.startsWith("Bearer ")) {
      return respond({ error: "Authentication required" }, 401);
    }

    const supabaseUrl = Deno.env.get("SUPABASE_URL");
    const anonKey =
      Deno.env.get("SUPABASE_ANON_KEY") ??
      Deno.env.get("SUPABASE_PUBLISHABLE_KEY");
    const serviceRoleKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");

    if (!supabaseUrl || !anonKey || !serviceRoleKey) {
      console.error("Supabase function secrets are incomplete");
      return respond({ error: "Server configuration error" }, 500);
    }

    const userClient = createClient(supabaseUrl, anonKey, {
      global: { headers: { Authorization: authorization } },
      auth: { persistSession: false, autoRefreshToken: false },
    });

    const { data: { user }, error: authError } =
      await userClient.auth.getUser();

    if (authError || !user) {
      return respond({ error: "Invalid or expired session" }, 401);
    }

    const admin = createClient(supabaseUrl, serviceRoleKey, {
      auth: { persistSession: false, autoRefreshToken: false },
    });

    const { data: profile, error: profileError } = await admin
      .from("profiles")
      .select("role, date_of_birth")
      .eq("id", user.id)
      .maybeSingle();

    if (profileError) {
      console.error("Host profile lookup failed");
      return respond({ error: "Unable to verify profile" }, 500);
    }

    if (!profile || profile.role !== "host") {
      return respond({ error: "Host account required" }, 403);
    }

    if (
      typeof profile.date_of_birth !== "string" ||
      !isAdult(profile.date_of_birth)
    ) {
      return respond({
        error: "A valid date of birth confirming age 18+ is required.",
      }, 403);
    }

    let body: Record<string, unknown>;
    try {
      const parsedBody: unknown = await req.json();
      if (!parsedBody || typeof parsedBody !== "object" || Array.isArray(parsedBody)) {
        return respond({ error: "Invalid request body" }, 400);
      }
      body = parsedBody as Record<string, unknown>;
    } catch {
      return respond({ error: "Invalid JSON request body" }, 400);
    }

    // Verified host onboarding is GPS-only. Client-supplied manual country data
    // must never be treated as a verified location.
    if (body.mode !== "gps") {
      return respond({
        error: "GPS verification is required to complete host onboarding",
      }, 400);
    }

    const latitude = body.latitude;
    const longitude = body.longitude;
    const accuracy = body.accuracy_meters;

    if (
      typeof latitude !== "number" || !Number.isFinite(latitude) ||
      typeof longitude !== "number" || !Number.isFinite(longitude) ||
      latitude < -90 || latitude > 90 ||
      longitude < -180 || longitude > 180 ||
      typeof accuracy !== "number" || !Number.isFinite(accuracy) ||
      accuracy < 0 || accuracy > 5000
    ) {
      return respond({ error: "Invalid or insufficiently accurate GPS data" }, 400);
    }

    const location = await reverseGeocode(latitude, longitude);

    const { error: updateError } = await admin
      .from("profiles")
      .update({
        country_code: location.country_code,
        country: location.country,
        continent: location.continent,
        location_source: "gps",
        location_verified_at: new Date().toISOString(),
        host_onboarding_completed: true,
      })
      .eq("id", user.id)
      .eq("role", "host");

    if (updateError) {
      console.error("Failed to save host onboarding details");
      return respond({ error: "Could not save onboarding details" }, 500);
    }

    return respond({
      success: true,
      message: "Host onboarding completed.",
      location: {
        country_code: location.country_code,
        country: location.country,
        continent: location.continent,
        source: "gps",
      },
    });
  } catch (error) {
    console.error("Host location setup failed", error);
    return respond({ error: "Unable to complete location setup" }, 500);
  }
});
