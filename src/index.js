export default {
  async fetch(request, env) {
    const url = new URL(request.url);

    // Redirect legacy workers.dev URL to custom domain
    if (url.hostname.endsWith('.workers.dev')) {
      url.hostname = 'season2.homerslotr.com';
      return Response.redirect(url.toString(), 301);
    }

    // Otherwise serve the static asset as normal
    return env.ASSETS.fetch(request);
  }
};
