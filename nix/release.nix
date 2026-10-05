{
  # Upstream tag. The image label inside 7.2.5 still says v7.2.4; the
  # waf-service binary reports 7.2.5. Pin the digest, not the moving tag.
  version = "7.2.5";
  imageName = "docker.io/uusec/waf";
  imageDigest = "sha256:d7061e418ed5dd705f084091edc8fbb75c73bf369a4674699fe55ad910c2c574";
  # SRI of the skopeo docker-archive produced by dockerTools.pullImage.
  # Replace with lib.fakeHash and rebuild once when bumping imageDigest.
  imageHash = "sha256-QCxuvpuAGhO1O3nfsNgrL3zA/kCjwMyFZrjKIElKZ5A=";
}
