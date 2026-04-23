# [derrek.dev](https://derrek.dev)

Personal technical blog covering embedded systems, GPU computing, DevOps automation, and scientific computing.

## Topics

- **Radiation Effects** — SEU cross-section analysis, Weibull fitting, statistical methods
- **Embedded Linux** — Yocto/Poky builds, Docker containerization, BSP development
- **GPU Computing** — CUDA optimization, cache march tests, telemetry pipelines
- **Trading Systems** — Real-time data pipelines, event-driven architecture, technical indicators
- **Presentations** — SlideForge (Manim + Beamer hybrid system), LaTeX/Beamer techniques
- **DevOps** — Docker Compose patterns, Makefile automation, CI/CD pipelines
- **Security** — CAC/PIV smartcards, SSH hardening, VPS deployment

## Local Development

```bash
bundle install
bundle exec jekyll serve --drafts --future
```

## Deployment

Development happens on `dev` branch. Deploy to `main` with:

```bash
./tools/deploy.sh
```

This squash-merges all dev commits into a single commit on main, which triggers GitHub Pages deployment.

## License

Content is copyright Derrek Landauer. Theme based on [Chirpy](https://github.com/cotes2020/jekyll-theme-chirpy) (MIT). Color scheme based on [Rosé Pine Moon](https://rosepinetheme.com/) (MIT).
