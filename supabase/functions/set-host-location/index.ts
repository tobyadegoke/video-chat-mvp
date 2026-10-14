
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

function respond(body: unknown, status = 200) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...corsHeaders, "Content-Type": "application/json" },
  });
}

function isAdult(dob: string): boolean {
  if (!/^\d{4}-\d{2}-\d{2}$/.test(dob)) return false;

  const parsed = new Date(`${dob}T00:00:00.000Z`);
  if (Number.isNaN(parsed.getTime()) || parsed.toISOString().slice(0, 10) !== dob) {
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
  const url = new URL("https://nominatim.openstreetmap.org/reverse");
  url.searchParams.set("format", "jsonv2");
  url.searchParams.set("lat", String(latitude));
  url.searchParams.set("lon", String(longitude));
  url.searchParams.set("zoom", "3");
  url.searchParams.set("addressdetails", "1");

  const response = await fetch(url, {
    headers: { "User-Agent": "VideoPlatformHostOnboarding/1.0" },
  });

  if (!response.ok) throw new Error("Reverse geocoding failed");

  const data = await response.json();
  const address = data?.address;

  if (!address?.country || !address?.country_code) {
    throw new Error("Could not determine a country from this location");
  }

  const countryCode = String(address.country_code).toUpperCase();

  const countryResponse = await fetch(
    `https://restcountries.com/v3.1/alpha/${encodeURIComponent(countryCode)}?fields=name,region,subregion`,
  );

  if (!countryResponse.ok) throw new Error("Country lookup failed");

  const countryData = await countryResponse.json();
  const country = Array.isArray(countryData) ? countryData[0] : countryData;
  const region = country?.region;
  const subregion = country?.subregion ?? "";

  let continent: string;

  if (region === "Africa") {
    continent = "Africa";
  } else if (region === "Asia") {
    continent = "Asia";
  } else if (region === "Europe") {
    continent = "Europe";
  } else if (region === "Oceania") {
    continent = "Oceania";
  } else if (region === "Americas") {
    continent = subregion.toLowerCase().includes("south america")
      ? "South America"
      : subregion.toLowerCase().includes("central america") ||
          subregion.toLowerCase().includes("caribbean") ||
          subregion.toLowerCase().includes("north america")
        ? "North America"
        : "";
  } else if (country?.name?.common === "Antarctica") {
    continent = "Antarctica";
  } else {
    continent = "";
  }

  if (!allowedContinents.has(continent)) {
    throw new Error("Could not determine the continent for this country");
  }

  return {
    country_code: countryCode,
    country: String(country?.name?.common ?? address.country),
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

    const body = await req.json();
    let location: {
      country_code: string;
      country: string;
      continent: string;
    };
    let locationSource: "gps" | "manual";

    if (body.mode === "gps") {
      const latitude = Number(body.latitude);
      const longitude = Number(body.longitude);
      const accuracy = Number(body.accuracy_meters);

      if (
        !Number.isFinite(latitude) ||
        !Number.isFinite(longitude) ||
        latitude < -90 || latitude > 90 ||
        longitude < -180 || longitude > 180 ||
        !Number.isFinite(accuracy) ||
        accuracy < 0 || accuracy > 5000
      ) {
        return respond({ error: "Invalid or insufficiently accurate GPS data" }, 400);
      }

      location = await reverseGeocode(latitude, longitude);
      locationSource = "gps";
    } else if (body.mode === "manual") {
      const countryCode = String(body.country_code ?? "").trim().toUpperCase();
      const country = String(body.country ?? "").trim();
      const continent = String(body.continent ?? "").trim();

      if (
        !/^[A-Z]{2}$/.test(countryCode) ||
        country.length < 2 ||
        country.length > 100 ||
        !allowedContinents.has(continent)
      ) {
        return respond({ error: "Invalid manual location details" }, 400);
      }

      location = {
        country_code: countryCode,
        country,
        continent,
      };
      locationSource = "manual";
    } else {
      return respond({ error: "Unsupported location mode" }, 400);
    }

    const { error: updateError } = await admin
      .from("profiles")
      .update({
        country_code: location.country_code,
        country: location.country,
        continent: location.continent,
        location_source: locationSource,
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
        source: locationSource,
      },
    });
  } catch (error) {
    console.error("Host location setup failed", error);
    return respond({ error: "Unable to complete location setup" }, 500);
  }
});
