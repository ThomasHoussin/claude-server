# Claude Server - Instructions pour Claude Code

## Contexte

Projet CDK déployant un environnement de développement remote sur AWS : EC2 (ARM64) + code-server (VS Code browser) + Claude Code CLI.

## Fichiers clés

- `lib/claude-server-stack.ts` - Stack CDK principale (VPC, SG, EC2, Elastic IP optionnel, DNS optionnel)
- `config/config.ts` - Configuration sensible (gitignored) - copier depuis `config.example.ts`
- `scripts/init.sh` - Script user-data EC2 (installe nginx, code-server, certbot, Claude CLI)
- `bin/claude-server.ts` - Point d'entrée CDK

## Règles importantes

1. **NE JAMAIS commit `config/config.ts`** - contient des secrets (passwords, domain)
2. SSH ouvert à 0.0.0.0/0 - c'est intentionnel pour flexibilité avec Termius
3. DNS géré par CDK (pas par l'instance EC2) - si `useElasticIp: true` + `hostedZoneId` fourni
4. L'instance n'a que les permissions SSM, pas Route 53

## Configuration

Options dans `config/config.ts` :
- `region` - Région AWS
- `domain` - Domaine pour code-server
- `hostedZoneId` - Zone Route 53 (optionnel, pour DNS auto)
- `useElasticIp` - Utiliser une IP statique (optionnel, défaut: false)
- `codeServerPassword` - Mot de passe VS Code web
- `email` - Email Let's Encrypt
- `keyPairName` - Paire de clés EC2
- `instanceType` - Type d'instance (défaut: t4g.small)
- `volumeSize` - Taille EBS en GB

## Commandes

```bash
cdk synth    # Générer CloudFormation
cdk deploy   # Déployer
cdk diff     # Voir les changements
cdk destroy  # Supprimer
npm test     # Tests
```

## Debugging

- Logs user-data : `/var/log/user-data.log`
- Logs code-server : `journalctl -u code-server@ec2-user`
- Logs nginx : `/var/log/nginx/error.log`
