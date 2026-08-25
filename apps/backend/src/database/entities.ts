import { UserEntity } from '../users/entities/user.entity';

/**
 * Единый список сущностей — используется в DatabaseModule (Nest),
 * standalone DataSource (TypeORM CLI) и в reset-db.ts.
 * Добавляйте новые сущности сюда, а не в отдельных модулях.
 */
export const ENTITIES = [UserEntity];