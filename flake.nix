{
  description = "Reproducible Nix entrypoint for the Vexa meeting stack";

  nixConfig = {
    extra-substituters = [ "https://cache.numtide.com" ];
    extra-trusted-public-keys = [
      "niks3.numtide.com-1:DTx8wZduET09hRmMtKdQDxNNthLQETkc/yaX7M4qK0g="
    ];
  };

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-unstable";
    flake-utils.url = "github:numtide/flake-utils";
    garage-nix = {
      url = "github:kuro1981/garage-nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    llm-agents.url = "github:numtide/llm-agents.nix";

    pyproject-nix = {
      url = "github:pyproject-nix/pyproject.nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    uv2nix = {
      url = "github:pyproject-nix/uv2nix";
      inputs.nixpkgs.follows = "nixpkgs";
      inputs.pyproject-nix.follows = "pyproject-nix";
    };

    pyproject-build-systems = {
      url = "github:pyproject-nix/build-system-pkgs";
      inputs.nixpkgs.follows = "nixpkgs";
      inputs.pyproject-nix.follows = "pyproject-nix";
      inputs.uv2nix.follows = "uv2nix";
    };
  };

  outputs =
    { self
    , nixpkgs
    , flake-utils
    , garage-nix
    , llm-agents
    , pyproject-nix
    , uv2nix
    , pyproject-build-systems
    ,
    }:
    let
      inherit (nixpkgs) lib;
      vexaOwner = "vexa-ai";
      vexaRepo = "vexa";
      vexaRev = "e0b356d6de3f8322db45d3cb9d66282ae108bebf";
      vexaHash = "sha256-oI6+qujsVi2ymixzqipfBDL8vvZaSiWb/wmnv4TrtJc=";
      supportedSystems = [
        "x86_64-linux"
        "aarch64-linux"
        "aarch64-darwin"
      ];
    in
    flake-utils.lib.eachSystem supportedSystems (system:
    let
      pkgs = import nixpkgs { inherit system; };
      garagePackage = lib.attrByPath [ "packages" system "default" ] null garage-nix;
      garagePackages = lib.optional (garagePackage != null) garagePackage;
      llmAgentsPkgs = llm-agents.packages.${system};
      vexaSource = pkgs.fetchFromGitHub {
        owner = vexaOwner;
        repo = vexaRepo;
        rev = vexaRev;
        hash = vexaHash;
      };

      runtimeWorkspace = uv2nix.lib.workspace.loadWorkspace {
        workspaceRoot = "${vexaSource}/core/runtime";
      };

      runtimeServerWorkspace = uv2nix.lib.workspace.loadWorkspace {
        workspaceRoot = ./nix/uvicorn;
      };

      gatewayWorkspace = uv2nix.lib.workspace.loadWorkspace {
        workspaceRoot = "${vexaSource}/core/gateway/services/gateway";
      };

      gatewayProductionWorkspace = uv2nix.lib.workspace.loadWorkspace {
        workspaceRoot = ./nix/gateway;
      };

      meetingApiWorkspace = uv2nix.lib.workspace.loadWorkspace {
        workspaceRoot = "${vexaSource}/core/meetings/services/meeting-api";
      };

      meetingApiProductionWorkspace = uv2nix.lib.workspace.loadWorkspace {
        workspaceRoot = ./nix/meeting-api;
      };

      adminApiWorkspace = uv2nix.lib.workspace.loadWorkspace {
        workspaceRoot = "${vexaSource}/core/identity/services/admin-api";
      };

      adminApiProductionWorkspace = uv2nix.lib.workspace.loadWorkspace {
        workspaceRoot = ./nix/admin-api;
      };

      agentWorkspace = uv2nix.lib.workspace.loadWorkspace {
        workspaceRoot = "${vexaSource}/core/agent";
      };

      mcpWorkspace = uv2nix.lib.workspace.loadWorkspace {
        workspaceRoot = "${vexaSource}/core/meetings/services/mcp";
      };

      runtimeOverlay = runtimeWorkspace.mkPyprojectOverlay {
        sourcePreference = "wheel";
      };

      runtimeServerOverlay = runtimeServerWorkspace.mkPyprojectOverlay {
        sourcePreference = "wheel";
      };

      gatewayOverlay = gatewayWorkspace.mkPyprojectOverlay {
        sourcePreference = "wheel";
      };

      gatewayProductionOverlay = gatewayProductionWorkspace.mkPyprojectOverlay {
        sourcePreference = "wheel";
      };

      meetingApiOverlay = meetingApiWorkspace.mkPyprojectOverlay {
        sourcePreference = "wheel";
      };

      meetingApiProductionOverlay = meetingApiProductionWorkspace.mkPyprojectOverlay {
        sourcePreference = "wheel";
      };

      adminApiOverlay = adminApiWorkspace.mkPyprojectOverlay {
        sourcePreference = "wheel";
      };

      adminApiProductionOverlay = adminApiProductionWorkspace.mkPyprojectOverlay {
        sourcePreference = "wheel";
      };

      agentOverlay = agentWorkspace.mkPyprojectOverlay {
        sourcePreference = "wheel";
      };

      mcpOverlay = mcpWorkspace.mkPyprojectOverlay {
        sourcePreference = "wheel";
      };

      runtimePython = pkgs.python312;
      runtimePythonSet =
        (pkgs.callPackage pyproject-nix.build.packages {
          python = runtimePython;
        }).overrideScope
          (lib.composeManyExtensions [
            pyproject-build-systems.overlays.wheel
            runtimeOverlay
            runtimeServerOverlay
          ]);

      runtimeEnv = runtimePythonSet.mkVirtualEnv "vexa-runtime-env" (
        runtimeWorkspace.deps.default // runtimeServerWorkspace.deps.default
      );

      gatewayPythonSet =
        (pkgs.callPackage pyproject-nix.build.packages {
          python = runtimePython;
        }).overrideScope
          (lib.composeManyExtensions [
            pyproject-build-systems.overlays.wheel
            gatewayOverlay
            gatewayProductionOverlay
          ]);

      gatewayEnv = gatewayPythonSet.mkVirtualEnv "vexa-gateway-env" (
        gatewayWorkspace.deps.default // gatewayProductionWorkspace.deps.default
      );

      meetingApiPythonSet =
        (pkgs.callPackage pyproject-nix.build.packages {
          python = runtimePython;
        }).overrideScope
          (lib.composeManyExtensions [
            pyproject-build-systems.overlays.wheel
            meetingApiOverlay
            meetingApiProductionOverlay
          ]);

      meetingApiEnv = meetingApiPythonSet.mkVirtualEnv "vexa-meeting-api-env" (
        meetingApiWorkspace.deps.default // meetingApiProductionWorkspace.deps.default
      );

      adminApiPythonSet =
        (pkgs.callPackage pyproject-nix.build.packages {
          python = runtimePython;
        }).overrideScope
          (lib.composeManyExtensions [
            pyproject-build-systems.overlays.wheel
            adminApiOverlay
            adminApiProductionOverlay
          ]);

      adminApiEnv = adminApiPythonSet.mkVirtualEnv "vexa-admin-api-env" (
        adminApiWorkspace.deps.default // adminApiProductionWorkspace.deps.default
      );

      agentPythonSet =
        (pkgs.callPackage pyproject-nix.build.packages {
          python = runtimePython;
        }).overrideScope
          (lib.composeManyExtensions [
            pyproject-build-systems.overlays.wheel
            agentOverlay
          ]);

      agentEnv = agentPythonSet.mkVirtualEnv "vexa-agent-env" {
        "vexa-agent" = [ "control-plane" ];
      };

      agentWorkerEnv = agentPythonSet.mkVirtualEnv "vexa-agent-worker-env" (
        agentWorkspace.deps.default
      );

      mcpPythonSet =
        (pkgs.callPackage pyproject-nix.build.packages {
          python = runtimePython;
        }).overrideScope
          (lib.composeManyExtensions [
            pyproject-build-systems.overlays.wheel
            mcpOverlay
            runtimeServerOverlay
          ]);

      mcpEnv = mcpPythonSet.mkVirtualEnv "vexa-mcp-env" (
        mcpWorkspace.deps.default // runtimeServerWorkspace.deps.default
      );

      terminalPackage = pkgs.buildNpmPackage {
        pname = "vexa-terminal";
        version = vexaRev;
        src = "${vexaSource}/clients/terminal";
        npmDepsHash = "sha256-nXFCq+gHpznyErWdSab9lA1xIG/7P34wkCsT4/XEgys=";
        npmBuildScript = "build";
        installPhase = ''
          mkdir -p "$out"
          cp -R ./. "$out/"
        '';
      };

      runtime-app = pkgs.writeShellApplication {
        name = "vexa-runtime";
        runtimeInputs = [ runtimeEnv agentWorkerEnv ];
        text = ''
          export RUNTIME_BACKEND=process
          export BROWSER_IMAGE="''${BROWSER_IMAGE:-vexaai/vexa-bot:v012}"
          export BOT_COMMAND="${bot-docker-launcher}/bin/vexa-bot-docker-launcher"
          export AGENT_WORKER_COMMAND="${agent-worker-app}/bin/vexa-agent-worker"
          export PYTHONPATH="${vexaSource}/core/runtime/src''${PYTHONPATH:+:$PYTHONPATH}"
          exec python -m runtime_kernel "$@"
        '';
      };

      gateway-app = pkgs.writeShellApplication {
        name = "vexa-gateway";
        runtimeInputs = [ gatewayEnv ];
        text = ''
          export PYTHONPATH="${vexaSource}/core/gateway/services/gateway/src''${PYTHONPATH:+:$PYTHONPATH}"
          exec python -m gateway "$@"
        '';
      };

      meeting-api-app = pkgs.writeShellApplication {
        name = "vexa-meeting-api";
        runtimeInputs = [ meetingApiEnv ];
        text = ''
          export PYTHONPATH="${vexaSource}/core/meetings/services/meeting-api/src''${PYTHONPATH:+:$PYTHONPATH}"
          exec python -m meeting_api "$@"
        '';
      };

      admin-api-app = pkgs.writeShellApplication {
        name = "vexa-admin-api";
        runtimeInputs = [ adminApiEnv ];
        text = ''
          export PYTHONPATH="${vexaSource}/core/identity/services/admin-api/src''${PYTHONPATH:+:$PYTHONPATH}"
          exec python -m admin_api "$@"
        '';
      };

      agent-api-app = pkgs.writeShellApplication {
        name = "vexa-agent-api";
        runtimeInputs = [ agentEnv ];
        text = ''
          export PYTHONPATH="${vexaSource}/core/agent''${PYTHONPATH:+:$PYTHONPATH}"
          exec uvicorn control_plane.api:app --host 0.0.0.0 --port 8100 "$@"
        '';
      };

      agent-worker-app = pkgs.writeShellApplication {
        name = "vexa-agent-worker";
        runtimeInputs = [ agentWorkerEnv llmAgentsPkgs.claude-code pkgs.git ];
        text = ''
          export PYTHONPATH="${vexaSource}/core/agent''${PYTHONPATH:+:$PYTHONPATH}"
          export VEXA_WORKSPACE_SEEDS_DIR="''${VEXA_WORKSPACE_SEEDS_DIR:-${vexaSource}/core/agent/workspace-seeds}"
          export VEXA_TOOLS_SEED_DIR="''${VEXA_TOOLS_SEED_DIR:-${vexaSource}/core/agent/tools-seed}"
          exec python -m worker "$@"
        '';
      };

      bot-docker-launcher = pkgs.writeShellApplication {
        name = "vexa-bot-docker-launcher";
        runtimeInputs = [ pkgs.docker ];
        text = ''
          image="''${VEXA_BOT_IMAGE:-''${BROWSER_IMAGE:-vexaai/vexa-bot:v012}}"
          network="''${VEXA_DOCKER_NETWORK:-host}"
          docker_bin="''${VEXA_DOCKER_BIN:-docker}"
          env_args=()
          for name in \
            VEXA_BOT_CONFIG \
            REDIS_URL \
            BOT_S3_ACCESS_KEY \
            BOT_S3_BUCKET \
            BOT_S3_ENDPOINT \
            BOT_S3_SECRET_KEY \
            BOT_UI_LOCALE \
            BOT_USERDATA_S3_PATH \
            BROWSER_DATA_DIR \
            DEFAULT_BOT_NAME \
            ENCODE_H264 \
            LOGIN_PROFILE_DIR \
            LOGIN_TIMEOUT_MS \
            PULSE_SINK \
            TTS_API_TOKEN \
            TTS_SERVICE_URL \
            VEXA_BROWSER_UTILS_PATH \
            VEXA_CAPTURE_SIGNAL_DIR \
            VEXA_HARVEST_LANGS \
            VEXA_HF_CACHE \
            VEXA_RECORDING_TIMESLICE_MS \
            VEXA_SEG_DEBUG \
            VEXA_STT_MODEL \
            VEXA_TX_KEY \
            VEXA_TX_URL \
            VIDEO_HWACCEL; do
            env_args+=(--env "$name")
          done

          exec "$docker_bin" run --rm --init --network "$network" \
            "''${env_args[@]}" "$image" "$@"
        '';
      };

      mcp-app = pkgs.writeShellApplication {
        name = "vexa-mcp";
        runtimeInputs = [ mcpEnv ];
        text = ''
          export PYTHONPATH="${vexaSource}/core/meetings/services/mcp/src''${PYTHONPATH:+:$PYTHONPATH}"
          exec python -m vexa_mcp "$@"
        '';
      };

      terminal-app = pkgs.writeShellApplication {
        name = "vexa-terminal";
        runtimeInputs = [ pkgs.nodejs_22 ];
        text = ''
          export NODE_ENV=production
          cd "${terminalPackage}"
          exec node server.mjs "$@"
        '';
      };

      vexa-infra = pkgs.writeShellApplication {
        name = "vexa-infra";
        runtimeInputs = [ pkgs.coreutils pkgs.gnugrep pkgs.postgresql_17 pkgs.valkey ];
        text = ''
                    set -euo pipefail

                    state_dir="''${VEXA_INFRA_STATE_DIR:-''${XDG_STATE_HOME:-$HOME/.local/state}/vexa}"
                    postgres_port="''${POSTGRES_PORT:-5432}"
                    valkey_port="''${VALKEY_PORT:-6379}"
                    postgres_password="''${POSTGRES_PASSWORD:-postgres}"
                    database_name="''${POSTGRES_DB:-vexa}"
                    escaped_password="''${postgres_password//\'/\'\'}"
                    escaped_database_name="''${database_name//\'/\'\'}"
                    postgres_dir="$state_dir/postgres"
                    valkey_dir="$state_dir/valkey"
                    postgres_pid=""
                    valkey_pid=""
                    mkdir -p "$state_dir" "$valkey_dir"

                    if [[ ! -f "$postgres_dir/PG_VERSION" ]]; then
                      mkdir -p "$postgres_dir"
                      initdb --no-locale --encoding=UTF8 --auth=trust --username=postgres -D "$postgres_dir" >/dev/null
                    fi

                    postgres -D "$postgres_dir" \
                      -h 127.0.0.1 -k "$state_dir" -p "$postgres_port" \
                      >"$state_dir/postgres.log" 2>&1 &
                    postgres_pid=$!

                    cleanup() {
                      kill "$valkey_pid" "$postgres_pid" 2>/dev/null || true
                      wait "$valkey_pid" "$postgres_pid" 2>/dev/null || true
                    }
                    trap cleanup EXIT INT TERM

                    for _ in {1..50}; do
                      if pg_isready -h 127.0.0.1 -p "$postgres_port" >/dev/null 2>&1; then
                        break
                      fi
                      sleep 0.1
                    done
                    pg_isready -h 127.0.0.1 -p "$postgres_port" >/dev/null

                    psql -h 127.0.0.1 -p "$postgres_port" -U postgres -d postgres \
                      -v ON_ERROR_STOP=1 \
                      -c "ALTER USER postgres PASSWORD '$escaped_password'" >/dev/null
                    if ! psql -h 127.0.0.1 -p "$postgres_port" -U postgres -d postgres -At \
                      -c "SELECT 1 FROM pg_database WHERE datname = '$escaped_database_name'" | grep -qx 1; then
                      createdb -h 127.0.0.1 -p "$postgres_port" -U postgres "$database_name"
                    fi

                    valkey-server \
                      --bind 127.0.0.1 --port "$valkey_port" \
                      --dir "$valkey_dir" --save "" --appendonly no \
                      >"$state_dir/valkey.log" 2>&1 &
                    valkey_pid=$!
                    for _ in {1..50}; do
                      if valkey-cli -h 127.0.0.1 -p "$valkey_port" ping 2>/dev/null | grep -qx PONG; then
                        break
                      fi
                      sleep 0.1
                    done
                    valkey-cli -h 127.0.0.1 -p "$valkey_port" ping | grep -qx PONG

                    cat <<EOF
          Vexa local infrastructure is ready.
            PostgreSQL: postgresql://postgres:$postgres_password@127.0.0.1:$postgres_port/$database_name
            Valkey:     redis://127.0.0.1:$valkey_port/0
            State:      $state_dir

          Press Ctrl-C to stop both services.
          EOF
                    wait "$postgres_pid" "$valkey_pid"
        '';
      };

      vexa-source = pkgs.runCommand "vexa-source-${builtins.substring 0 12 vexaRev}" { } ''
        mkdir -p "$out/share/vexa"
        cp -R ${vexaSource}/. "$out/share/vexa/"
      '';

      garageConfig = pkgs.writeText "garage-compose.toml" ''
        metadata_dir = "/var/lib/garage/meta"
        data_dir = "/var/lib/garage/data"
        db_engine = "sqlite"
        replication_factor = 1
        rpc_bind_addr = "0.0.0.0:3901"
        rpc_public_addr = "garage:3901"
        rpc_secret = "vexa-nix-compose-dev-rpc-secret"

        [s3_api]
        api_bind_addr = "0.0.0.0:3900"
        s3_region = "garage"
      '';

      garageImage =
        if garagePackage == null then
          null
        else
          pkgs.dockerTools.buildImage {
            name = "vexa-nix/garage";
            tag = "2.3.0";
            copyToRoot = pkgs.buildEnv {
              name = "garage-compose-root";
              paths = [ garagePackage ];
              pathsToLink = [ "/bin" ];
            };
            extraCommands = ''
              mkdir -p etc var/lib/garage/meta var/lib/garage/data
              cp ${garageConfig} etc/garage.toml
            '';
            config = {
              Cmd = [ "${garagePackage}/bin/garage" "server" "--single-node" "--default-bucket" ];
              Env = [ "GARAGE_CONFIG_FILE=/etc/garage.toml" ];
            };
          };
      garageImagePath = if garageImage == null then "" else garageImage;

      vexa-compose = pkgs.writeShellApplication {
        name = "vexa-compose";
        runtimeInputs = [ pkgs.coreutils pkgs.docker pkgs.docker-compose ];
        text = ''
          set -euo pipefail

          if command -v docker-compose >/dev/null 2>&1 && docker-compose version >/dev/null 2>&1; then
            compose=(docker-compose)
          elif command -v docker >/dev/null 2>&1 && docker compose version >/dev/null 2>&1; then
            compose=(docker compose)
          else
            echo "No Docker Compose provider found; install docker-compose or enable the Docker Compose plugin." >&2
            exit 1
          fi

          source_root="''${VEXA_SOURCE:-}"
          if [[ -z "$source_root" ]]; then
            source_root="${vexaSource}"
          fi

          if [[ ! -d "$source_root/deploy/compose" ]]; then
            echo "VEXA_SOURCE does not contain deploy/compose: $source_root" >&2
            exit 1
          fi

          workdir="$(mktemp -d "''${TMPDIR:-/tmp}/vexa-nix.XXXXXX")"
          trap 'rm -rf "$workdir"' EXIT
          cp -R "$source_root"/. "$workdir/"
          chmod -R u+w "$workdir"
          if [[ -f "$PWD/.env" ]]; then
            cp "$PWD/.env" "$workdir/deploy/compose/.env"
          elif [[ -f "$PWD/deploy/compose/.env" ]]; then
            cp "$PWD/deploy/compose/.env" "$workdir/deploy/compose/.env"
          fi
          cd "$workdir/deploy/compose"

          if [[ "''${VEXA_OBJECT_STORE:-minio}" == garage ]]; then
            garage_image_path="${garageImagePath}"
            if [[ -z "$garage_image_path" ]]; then
              echo "Garage is not available for system ${system}." >&2
              exit 1
            fi

            docker_bin="''${VEXA_DOCKER_BIN:-docker}"
            "$docker_bin" load --input "$garage_image_path" >/dev/null
            garage_access_key="''${GARAGE_ACCESS_KEY:-vexa-recordings-access}"
            garage_secret_key="''${GARAGE_SECRET_KEY:-vexa-recordings-secret}"
            garage_bucket="''${RECORDING_BUCKET:-vexa-recordings}"
            garage_endpoint="''${GARAGE_ENDPOINT:-garage:3900}"
            garage_secure="''${GARAGE_SECURE:-false}"

            cat > .docker-compose.garage.yml <<EOF
          services:
            minio:
              profiles: ["minio"]
            minio-init:
              profiles: ["minio"]
            garage:
              image: vexa-nix/garage:2.3.0
              environment:
                GARAGE_DEFAULT_ACCESS_KEY: $garage_access_key
                GARAGE_DEFAULT_SECRET_KEY: $garage_secret_key
                GARAGE_DEFAULT_BUCKET: $garage_bucket
              healthcheck:
                test: ["CMD", "garage", "status"]
                interval: 5s
                timeout: 5s
                retries: 12
              volumes:
                - garage-meta:/var/lib/garage/meta
                - garage-data:/var/lib/garage/data
              networks: [vexa]
              restart: unless-stopped
            meeting-api:
              environment:
                MINIO_ENDPOINT: $garage_endpoint
                MINIO_ACCESS_KEY: $garage_access_key
                MINIO_SECRET_KEY: $garage_secret_key
                MINIO_BUCKET: $garage_bucket
                MINIO_SECURE: $garage_secure
              depends_on: !override
                postgres:
                  condition: service_healthy
                redis:
                  condition: service_healthy
                runtime:
                  condition: service_healthy
                garage:
                  condition: service_healthy
          volumes:
            garage-meta:
            garage-data:
          EOF
            exec "''${compose[@]}" -f docker-compose.yml -f .docker-compose.garage.yml "$@"
          fi

          exec "''${compose[@]}" "$@"
        '';
      };
    in
    {
      packages = {
        default = vexa-source;
        vexa-source = vexa-source;
        vexa-compose = vexa-compose;
        vexa-runtime-env = runtimeEnv;
        vexa-runtime = runtime-app;
        vexa-gateway-env = gatewayEnv;
        vexa-gateway = gateway-app;
        vexa-meeting-api-env = meetingApiEnv;
        vexa-meeting-api = meeting-api-app;
        vexa-admin-api-env = adminApiEnv;
        vexa-admin-api = admin-api-app;
        vexa-agent-api-env = agentEnv;
        vexa-agent-api = agent-api-app;
        vexa-agent-worker-env = agentWorkerEnv;
        vexa-agent-worker = agent-worker-app;
        vexa-bot-docker-launcher = bot-docker-launcher;
        vexa-mcp-env = mcpEnv;
        vexa-mcp = mcp-app;
        vexa-terminal = terminalPackage;
        vexa-infra = vexa-infra;
      };

      apps = {
        default = {
          type = "app";
          program = "${vexa-compose}/bin/vexa-compose";
          meta.description = "Run the pinned Vexa Docker Compose stack";
        };
        compose = {
          type = "app";
          program = "${vexa-compose}/bin/vexa-compose";
          meta.description = "Run the pinned Vexa Docker Compose stack";
        };
        runtime = {
          type = "app";
          program = "${runtime-app}/bin/vexa-runtime";
          meta.description = "Run the Nix-resolved Vexa runtime service";
        };
        gateway = {
          type = "app";
          program = "${gateway-app}/bin/vexa-gateway";
          meta.description = "Run the Nix-resolved Vexa gateway service";
        };
        meeting-api = {
          type = "app";
          program = "${meeting-api-app}/bin/vexa-meeting-api";
          meta.description = "Run the Nix-resolved Vexa meeting API service";
        };
        admin-api = {
          type = "app";
          program = "${admin-api-app}/bin/vexa-admin-api";
          meta.description = "Run the Nix-resolved Vexa admin API service";
        };
        agent-api = {
          type = "app";
          program = "${agent-api-app}/bin/vexa-agent-api";
          meta.description = "Run the Nix-resolved Vexa agent API service";
        };
        agent-worker = {
          type = "app";
          program = "${agent-worker-app}/bin/vexa-agent-worker";
          meta.description = "Run the Nix-resolved Vexa agent worker without Docker";
        };
        bot-docker-launcher = {
          type = "app";
          program = "${bot-docker-launcher}/bin/vexa-bot-docker-launcher";
          meta.description = "Run a Vexa meeting bot in Docker from the process backend";
        };
        mcp = {
          type = "app";
          program = "${mcp-app}/bin/vexa-mcp";
          meta.description = "Run the Nix-resolved Vexa MCP service";
        };
        terminal = {
          type = "app";
          program = "${terminal-app}/bin/vexa-terminal";
          meta.description = "Run the Nix-resolved Vexa terminal service";
        };
        infra = {
          type = "app";
          program = "${vexa-infra}/bin/vexa-infra";
          meta.description = "Run Vexa PostgreSQL and Valkey without Docker";
        };
      };

      devShells.default = pkgs.mkShell {
        packages = with pkgs; [
          git
          gh
          jq
          awscli2
          docker
          docker-compose
          nodejs_22
          nixpkgs-fmt
          openssl
          pnpm
          python312Packages.pytest
          python312Packages.pytest-asyncio
          runtimeEnv
          uv
        ] ++ garagePackages;

        shellHook = ''
          export VEXA_SOURCE="${vexaSource}"
          export VEXA_NIX_REV="${vexaRev}"
          export PYTEST_ADDOPTS="-o cache_dir=''${TMPDIR:-/tmp}/vexa-pytest-cache"
          export PYTHONPATH="${vexaSource}/core/runtime/src''${PYTHONPATH:+:$PYTHONPATH}"
          echo "Vexa source: $VEXA_NIX_REV"
          echo "Run 'nix run .#compose -- up' to start the pinned Compose stack."
        '';
      };

      formatter = pkgs.nixpkgs-fmt;
    }
    );
}
